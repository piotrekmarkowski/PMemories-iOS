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
    @AppStorage("selectedAvatarFrame") private var selectedAvatarFrameRawValue: String = AvatarFrame.none.rawValue

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var sortMode: LeaderboardSort = .score

    /// Ranking znajomych (28.08.2026) — osobny stan od globalnego, żeby
    /// przełączanie zakładek Global/Friends nie wymagało zapytania sieciowego
    /// za każdym razem (oba trzymane naraz, odświeżane razem przy
    /// `refresh()`/pull-to-refresh, patrz `FriendCircleService`).
    @State private var scope: LeaderboardScope = .global
    @State private var myCircle: FriendCircle?
    @State private var friendEntries: [LeaderboardEntry] = []
    @State private var isLoadingCircle = false
    @State private var joinCodeInput = ""
    @State private var circleErrorMessage: String?
    @State private var isShowingLeaveConfirm = false
    @State private var isCircleDetailsExpanded = false

    private var myScore: ExplorerScore {
        TravelAchievementsCalculator.explorerScore(from: savedTrips, projects: savedProjects)
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
        .task {
            if auth.isSignedIn {
                await refresh()
                await loadMyCircle()
            }
        }
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
                Picker("", selection: $scope) {
                    ForEach(LeaderboardScope.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .padding(.horizontal, -16)
            }

            if scope == .friends {
                circleSection
            }

            Section {
                Picker(L("Sort by"), selection: $sortMode) {
                    ForEach(LeaderboardSort.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: sortMode) { _, _ in
                    Task {
                        await refresh()
                        if myCircle != nil { await refreshFriends() }
                    }
                }
                .listRowBackground(Color.clear)
                .padding(.horizontal, -16)
            }

            if scope == .global || myCircle != nil {
                Section(L("Leaderboard")) {
                    let list = scope == .global ? entries : friendEntries
                    if list.isEmpty && !isLoading {
                        Text(scope == .global ? L("No entries yet — be the first!") : L("No one here yet — invite friends to compare scores!"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(rank: index + 1, entry: entry, isMe: entry.id == auth.userIdentifier, sortMode: sortMode)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .refreshable {
            await refresh()
            if myCircle != nil { await refreshFriends() }
        }
        .confirmationDialog(L("Leave this circle?"), isPresented: $isShowingLeaveConfirm, titleVisibility: .visible) {
            Button(L("Leave Circle"), role: .destructive) { Task { await leaveCircle() } }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("You'll need a new invite code to join again."))
        }
    }

    /// Zawartość zakładki "Friends" NAD samą listą wyników — albo kod
    /// zaproszenia + "Leave" (już w kręgu), albo formularz założenia/
    /// dołączenia (jeszcze w żadnym).
    @ViewBuilder
    private var circleSection: some View {
        if let myCircle {
            // Zwinięte domyślnie (29.08.2026, user: "za dużo miejsca
            // zajmuje... i tak jestem już na liście") — kod zaproszenia
            // istotny tylko RAZ, przy zakładaniu kręgu/zapraszaniu kogoś
            // nowego, nie za każdym wejściem w zakładkę Friends. Sam nagłówek
            // (bez rozwijania) już pokazuje kod, gdyby ktoś tylko potrzebował
            // szybko spojrzeć.
            Section {
                DisclosureGroup(isExpanded: $isCircleDetailsExpanded) {
                    HStack {
                        ShareLink(item: String(format: L("Join my PMemories circle! Code: %@"), myCircle.inviteCode)) {
                            Label(L("Invite Friends"), systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            isShowingLeaveConfirm = true
                        } label: {
                            Text(L("Leave Circle"))
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label {
                        Text("\(L("Invite Code")): \(myCircle.inviteCode)")
                            .font(.system(.body, design: .monospaced))
                    } icon: {
                        Image(systemName: "person.3.fill")
                    }
                }
            }
        } else {
            Section {
                Text(L("No circle yet — create one or join with a friend's code."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await createCircle() }
                } label: {
                    if isLoadingCircle {
                        ProgressView()
                    } else {
                        Text(L("Create a Circle"))
                    }
                }
                .disabled(isLoadingCircle)
                HStack {
                    TextField(L("Enter code"), text: $joinCodeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(L("Join")) { Task { await joinCircle() } }
                        .disabled(joinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingCircle)
                }
                if let circleErrorMessage {
                    Text(circleErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        do {
            try auth.handle(result: result)
            await refresh()
        } catch {
            errorMessage = LeaderboardService.friendlyMessage(for: error)
        }
    }

    private func refresh() async {
        isLoading = true
        isSubmitting = true
        defer { isLoading = false; isSubmitting = false }
        do {
            try await LeaderboardService.submitCurrentScore(
                score: myScore, km: myScore.totalKm, countries: myScore.rawCountries,
                cities: myScore.rawCities, elevationM: myScore.rawElevationM,
                avatarFrame: selectedAvatarFrameRawValue
            )
            entries = try await LeaderboardService.topEntries(sortBy: sortMode)
            errorMessage = nil
        } catch {
            errorMessage = LeaderboardService.friendlyMessage(for: error)
        }
    }

    private func loadMyCircle() async {
        isLoadingCircle = true
        defer { isLoadingCircle = false }
        // Świadomie po cichu — brak kręgu to normalny, oczekiwany stan
        // (jeszcze nikt nie stworzył/dołączył), nie błąd do pokazania.
        myCircle = try? await FriendCircleService.myCircle()
        if myCircle != nil { await refreshFriends() }
    }

    private func createCircle() async {
        isLoadingCircle = true
        circleErrorMessage = nil
        defer { isLoadingCircle = false }
        do {
            myCircle = try await FriendCircleService.createCircle()
            await refreshFriends()
        } catch {
            circleErrorMessage = error.localizedDescription
        }
    }

    private func joinCircle() async {
        isLoadingCircle = true
        circleErrorMessage = nil
        defer { isLoadingCircle = false }
        do {
            myCircle = try await FriendCircleService.joinCircle(code: joinCodeInput)
            joinCodeInput = ""
            await refreshFriends()
        } catch {
            circleErrorMessage = error.localizedDescription
        }
    }

    private func leaveCircle() async {
        do {
            try await FriendCircleService.leaveCurrentCircle()
            myCircle = nil
            friendEntries = []
        } catch {
            circleErrorMessage = error.localizedDescription
        }
    }

    private func refreshFriends() async {
        guard let myCircle else { friendEntries = []; return }
        do {
            var ids = Set(try await FriendCircleService.memberIDs(circleID: myCircle.id))
            // Bug znaleziony 29.08.2026 (user: "jak tworzymy ranking ze
            // znajomymi to my też tam musimy być") — `CKQuery` w
            // `memberIDs` bywa spóźniony względem świeżo zapisanego
            // rekordu (eventual consistency CloudKit dla zapytań, w
            // przeciwieństwie do odczytu wprost po ID) — zaraz po
            // `createCircle()`/`joinCircle()` własne członkostwo mogło
            // jeszcze nie być widoczne w wyniku zapytania mimo że
            // faktycznie istnieje w bazie. Dopisujemy siebie ręcznie —
            // skoro `myCircle` w ogóle istnieje, na pewno JESTEŚMY w nim
            // członkiem (właśnie to spowodowało), niezależnie od tego co
            // akurat zwróciło zapytanie.
            if let me = auth.userIdentifier { ids.insert(me) }
            friendEntries = try await LeaderboardService.entries(forUserIDs: Array(ids), sortBy: sortMode)
        } catch {
            circleErrorMessage = error.localizedDescription
        }
    }
}

private enum LeaderboardScope: String, CaseIterable, Identifiable {
    case global, friends

    var id: String { rawValue }
    var label: String {
        switch self {
        case .global: return L("Global")
        case .friends: return L("Friends")
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

    /// Ramka/odznaka pokazywana TYLKO na własnym wierszu (30.08.2026, user:
    /// "avatar żeby był widoczny w rankingu... żeby nie był za duży") —
    /// `LeaderboardEntry` z CloudKit nie ma ani zdjęcia, ani wybranej
    /// ramki innych userów (appka nigdy tego nie synchronizuje, tylko
    /// wynik), więc dla cudzych wierszy da się pokazać uczciwie tylko
    /// inicjał na gradiencie. Dla siebie mamy oba lokalnie.
    @AppStorage("selectedAvatarFrame") private var selectedAvatarFrameRawValue: String = AvatarFrame.none.rawValue

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
        HStack(spacing: 10) {
            Text(rankEmoji ?? "\(rank)")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 24)
            avatarView
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.system(size: 14, weight: isMe ? .bold : .regular))
                Text("\(Int(entry.km).formatted()) km · \(entry.countries) \(countriesLabel(entry.countries)) · \(entry.cities) \(citiesLabel(entry.cities))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailingValue)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.blue)
        }
        // Zagęszczone (30.08.2026, user: "przy 50 osobach będzie się
        // przewijać za długo") — mniejszy avatar, mniejsze fonty, i
        // jawne `.listRowInsets` (domyślne `List` zostawiają sporo
        // pionowego marginesu na wiersz niezależnie od zawartości).
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowBackground(isMe ? Palette.blue.opacity(0.12) : Color.clear)
    }

    /// 28pt — jeszcze zagęszczone 30.08.2026 (było 34pt), wyraźnie
    /// mniejsze niż na Home (72pt) czy Profile (84pt), żeby zmieścić się
    /// w rzędzie listy obok tekstu bez dominowania nad nim (user: "żeby
    /// nie był za duży"). Inicjał dla KAŻDEGO wiersza,
    /// nie tylko cudzych (30.08.2026, user: "zostawmy tylko ramkę i
    /// inicjały narazie") — appka nie synchronizuje zdjęć profilowych do
    /// publicznej bazy, więc nawet własny wiersz pokazuje inicjał, nie
    /// realne zdjęcie, dla spójności z resztą listy. Ramka/odznaka
    /// natomiast pokazuje się dla WSZYSTKICH, bo to (w przeciwieństwie do
    /// zdjęcia) już jest zsynchronizowane (`entry.avatarFrame`,
    /// `LeaderboardService.submitCurrentScore`).
    private var avatarView: some View {
        let size: CGFloat = 28
        return Text(String(entry.displayName.first ?? "?"))
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.heroGradient, in: Circle())
            .overlay {
                if entry.avatarFrame != .none {
                    AvatarFrameBadge(frame: entry.avatarFrame, avatarSize: size)
                } else {
                    switch TesterRegistry.badge(for: entry.id) {
                    case .founder:
                        AvatarFrameOverlay(color: Palette.founderAccent, iconName: "crown.fill", avatarSize: size)
                    case .tester:
                        AvatarFrameOverlay(color: Palette.testerAccent, iconName: "testtube.2", avatarSize: size)
                    case .none:
                        EmptyView()
                    }
                }
            }
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
