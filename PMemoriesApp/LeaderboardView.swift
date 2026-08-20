import SwiftUI
import SwiftData
import AuthenticationServices

/// Ranking testerów wg Explorer Score (02.08.2026) — reużywa dokładnie ten
/// sam wynik co ekran Achievements, tylko porównuje go między userami przez
/// CloudKit (`LeaderboardService`). Wymaga Sign in with Apple — bez tego
/// appka nie ma czym rozróżnić userów w publicznej bazie.
struct LeaderboardView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @Query(sort: \SavedProject.createdAt) private var savedProjects: [SavedProject]
    @StateObject private var auth = AuthManager.shared

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var sortMode: LeaderboardSort = .score

    private var myScore: ExplorerScore {
        TravelAchievementsCalculator.explorerScore(from: savedTrips)
    }

    private var seasonalProgress: SeasonalChallenge.Progress {
        SeasonalChallenge.currentProgress(trips: savedTrips, projects: savedProjects)
    }

    var body: some View {
        Group {
            if !auth.isSignedIn {
                signInPrompt
            } else {
                leaderboardList
            }
        }
        .navigationTitle(L("Ranking"))
        .task { if auth.isSignedIn { await refresh() } }
    }

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(Palette.heroGradient)
            Text(L("Compare your travels"))
                .font(.title3.bold())
            Text(L("Sign in to see how your Explorer Score compares with other testers."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task { await handleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leaderboardList: some View {
        List {
            Section {
                SeasonalChallengeCard(progress: seasonalProgress)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Your score"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(myScore.total).formatted())")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(L("Sort by"), selection: $sortMode) {
                    ForEach(LeaderboardSort.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: sortMode) { _, _ in Task { await refresh() } }
                .listRowBackground(Color.clear)
                .padding(.horizontal, -16)
            }

            Section(L("Leaderboard")) {
                if entries.isEmpty && !isLoading {
                    Text(L("No entries yet — be the first!"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry, isMe: entry.id == auth.userIdentifier, sortMode: sortMode)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .refreshable { await refresh() }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        do {
            try auth.handle(result: result)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() async {
        isLoading = true
        isSubmitting = true
        defer { isLoading = false; isSubmitting = false }
        do {
            try await LeaderboardService.submitCurrentScore(
                score: myScore, km: myScore.totalKm, countries: myScore.rawCountries,
                cities: myScore.rawCities, elevationM: myScore.rawElevationM
            )
            entries = try await LeaderboardService.topEntries(sortBy: sortMode)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Karta "Sezonowego wyzwania" nad rankingiem (10.08.2026) — czysto lokalna,
/// bez CloudKit (nie jest to porównanie z innymi userami, tylko osobisty
/// cel liczony z już zapisanych `SavedTrip`/`SavedProject`).
private struct SeasonalChallengeCard: View {
    let progress: SeasonalChallenge.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🏆 \(progress.seasonLabel) \(String(progress.year)) \(L("Challenge"))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if progress.isComplete {
                    Text(L("Complete!"))
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
            goalRow(
                icon: "flag.fill",
                text: "\(L("Visit a new country")) (\(progress.newCountriesDone)/\(progress.newCountriesTarget))",
                done: progress.newCountriesDone >= progress.newCountriesTarget
            )
            goalRow(
                icon: "film.fill",
                text: "\(L("Create 2 Memories")) (\(progress.newMemoriesDone)/\(progress.newMemoriesTarget))",
                done: progress.newMemoriesDone >= progress.newMemoriesTarget
            )
        }
        .padding(14)
        .background(Palette.heroGradient.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func goalRow(icon: String, text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .foregroundStyle(done ? .green : Palette.blue)
            Text(text)
                .font(.system(size: 13))
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isMe: Bool
    /// Duża liczba po prawej podąża za aktywnym sortowaniem (10.08.2026) —
    /// przy "Countries" pokazanie wciąż samych punktów byłoby mylące, skoro
    /// kolejność w liście jest ustalana przez zupełnie inną wartość.
    let sortMode: LeaderboardSort

    private var trailingValue: String {
        switch sortMode {
        case .score: return "\(Int(entry.score).formatted())"
        case .countries: return "\(entry.countries)"
        }
    }

    /// Ten sam bug co "7 Kraje"/"13 loty" na Home (11.08.2026) — `L(...)`
    /// zawsze pokazywał tę samą formę, poprawną tylko dla 2-4.
    private func countriesLabel(_ count: Int) -> String {
        guard isPolishLanguageActive else { return L("countries") }
        return polishPlural(count, one: "kraj", few: "kraje", many: "krajów")
    }

    private func citiesLabel(_ count: Int) -> String {
        guard isPolishLanguageActive else { return L("cities") }
        return polishPlural(count, one: "miasto", few: "miasta", many: "miast")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rankEmoji ?? "\(rank)")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 15, weight: isMe ? .bold : .regular))
                Text("\(Int(entry.km).formatted()) km · \(entry.countries) \(countriesLabel(entry.countries)) · \(entry.cities) \(citiesLabel(entry.cities))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailingValue)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.blue)
        }
        .padding(.vertical, 4)
        .listRowBackground(isMe ? Palette.blue.opacity(0.12) : Color.clear)
    }

    private var rankEmoji: String? {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }
}
