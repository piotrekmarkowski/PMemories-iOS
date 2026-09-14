import SwiftUI
import SwiftData

/// "Travel Achievements" — gamifikacja spinająca WSZYSTKIE środki transportu
/// i statystyki z zapisanych podróży (nie tylko Wędrówkę), zgodnie z opisem
/// w `Travel.md`. Dane liczone na żywo z `SavedTrip`/`SavedStop`
/// (`TravelAchievementsCalculator`) — żadnej osobnej persystencji "odznaka
/// odblokowana" nie ma sensu, bo status ZAWSZE wynika wprost z aktualnych,
/// realnych statystyk (usunięcie podróży poprawnie cofa odznakę, tak jak
/// powinno).
struct AchievementsView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @Query private var savedProjects: [SavedProject]
    /// Przekazywane od `TravelMapView` aż tutaj i dalej do `TripsListView` —
    /// "Edit" na zapisanej podróży musi wrócić do formularza na Travel Map,
    /// nie da się tego zrobić lokalnie skoro lista podróży (03.08.2026)
    /// przeniosła się na ten ekran.
    var onEditTrip: (SavedTrip) -> Void

    private var achievements: [Achievement] {
        TravelAchievementsCalculator.achievements(from: savedTrips)
    }

    private var aroundTheWorld: AroundTheWorldStat {
        TravelAchievementsCalculator.aroundTheWorld(from: savedTrips)
    }

    private var explorerScore: ExplorerScore {
        TravelAchievementsCalculator.explorerScore(from: savedTrips, projects: savedProjects)
    }

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    /// Kolejność wizualnej wagi kafelków — user 30.07.2026: "największa
    /// karta u góry Around the World, druga Countries, trzecia Cities,
    /// potem Flights, dopiero później środki transportu" — Kraje/Miasta/
    /// Loty jako pełnej szerokości wyróżnione wiersze nad resztą, żeby od
    /// razu prowadzić wzrok, reszta zostaje w mniejszej siatce 2 kolumn.
    private static let featuredIDs = ["countries", "cities", "flights"]

    private var featuredAchievements: [Achievement] {
        Self.featuredIDs.compactMap { id in achievements.first { $0.id == id } }
    }

    private var secondaryAchievements: [Achievement] {
        achievements.filter { !Self.featuredIDs.contains($0.id) }
    }

    private var hiddenBadges: [HiddenBadge] {
        TravelAchievementsCalculator.hiddenBadges(from: savedTrips, projects: savedProjects)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AroundTheWorldCard(stat: aroundTheWorld)
                    .padding(.horizontal)
                    .padding(.top, 8)

                NavigationLink {
                    ExplorerScoreBreakdownView(score: explorerScore)
                } label: {
                    ExplorerScoreCard(score: explorerScore)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // Lista zapisanych podróży — przeniesiona tu z góry ekranu
                // Travel Map (03.08.2026, user: przy ~50 podróżach nikt nie
                // będzie chciał przez nie przewijać, żeby dojść do formularza
                // budowania nowej trasy). Pierwsza w kolejności linków, bo to
                // najbardziej "podstawowa" treść z tych czterech.
                NavigationLink {
                    TripsListView(onEditTrip: onEditTrip)
                } label: {
                    SecondaryLinkRow(emoji: "🧳", title: L("Trips"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                NavigationLink {
                    TravelPassportView()
                } label: {
                    SecondaryLinkRow(emoji: "🛂", title: L("Travel Passport"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // Ranking testerów (02.08.2026, user: "ranking na
                // podstawie punktow, przebytych kilomotrow, krajow, miest
                // albo wzniesienia") — reużywa Explorer Score, porównuje
                // go między userami przez CloudKit + Sign in with Apple.
                NavigationLink {
                    LeaderboardView()
                } label: {
                    SecondaryLinkRow(emoji: "🏆", title: L("Ranking"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                NavigationLink {
                    TravelWrappedView()
                } label: {
                    SecondaryLinkRow(emoji: "📅", title: L("Travel Wrapped"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                NavigationLink {
                    TravelJourneyPosterView()
                } label: {
                    SecondaryLinkRow(emoji: "🗺️", title: L("My Travel Journey"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Text("\(unlockedCount) / \(achievements.count) \(L("badges unlocked"))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(featuredAchievements) { achievement in
                        NavigationLink {
                            AchievementDetailListView(achievement: achievement)
                        } label: {
                            FeaturedAchievementCard(achievement: achievement)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(secondaryAchievements) { achievement in
                        NavigationLink {
                            AchievementDetailListView(achievement: achievement)
                        } label: {
                            AchievementCard(achievement: achievement)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Ukryte odznaki (13.08.2026) — sekcja pojawia się TYLKO gdy
                // user faktycznie odblokował którąś, żeby zostały prawdziwą
                // niespodzianką ("easter egg"), nie kolejną listą "do
                // zdobycia" widoczną od pierwszego dnia.
                if !hiddenBadges.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("🥚 \(L("Secret Badges"))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(hiddenBadges) { badge in
                                HiddenBadgeCard(badge: badge)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Hero-kafelek na samej górze ekranu, przed listą pozostałych odznak — user
/// 30.07.2026 wprost: "musi być na pierwszym miejscu". Osobny format od
/// reszty (`AchievementCard`) — mnożnik zamiast progu, bo nigdy się nie
/// "kończy" (patrz `AroundTheWorldStat`).
private struct AroundTheWorldCard: View {
    let stat: AroundTheWorldStat

    /// "%" → "×" z powrotem (12/13.08.2026, user: "100% brzmi jak coś
    /// ukończonego... 1.0× = zrobiłem jedno okrążenie, ile zrobię dalej?").
    /// Cofnięcie zmiany z 01.08.2026 (wtedy: zewnętrzny feedback "większość
    /// ludzi nie myśli w x") — świadoma decyzja usera, gamifikacja > czysta
    /// intuicyjność formatu, ten sam mnożnik, tylko inaczej sformatowany.
    private var multiplierText: String {
        String(format: "%.1f×", stat.multiplier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("🌍")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(multiplierText) \(L("around the world"))")
                        .font(.title3.bold())
                    Text("\(Int(stat.totalDistanceKm.rounded()).formatted()) \(L("km travelled in total"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ProgressView(value: stat.progressToNextLap)
                .tint(Palette.blue)
            Text("\(Int(stat.remainingKmToNextLap.rounded()).formatted()) \(L("km to go until lap")) \(stat.lapsCompleted + 1) (1 \(L("lap")) = \(Int(AroundTheWorldStat.earthCircumferenceKm).formatted()) km)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.heroGradient.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.heroGradient, lineWidth: 1.5)
        )
    }
}

/// Drugi hero-kafelek, zaraz pod Around the World — user 30.07.2026 wybrał
/// prosty, jawny wzór punktowy zamiast czekać na prawdziwe AI (`ExplorerScore`
/// w `TravelAchievements.swift`). Tap → rozbicie punktacji, żeby nie było to
/// czarną skrzynką.
private struct ExplorerScoreCard: View {
    let score: ExplorerScore

    var body: some View {
        HStack(spacing: 12) {
            Text("🧭")
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Explorer Score")
                        .font(.headline)
                    Text(score.tierName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Palette.heroGradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                Text("\(Int(score.total).formatted()) \(L("pts"))")
                    .font(.title3.bold())
                    .foregroundStyle(Palette.blue)
                if let nextFloor = score.nextTierFloor {
                    Text("\(Int(nextFloor - score.total).formatted()) \(L("pts to the next level"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Top level — no ceiling, your score keeps growing")
                        .font(.caption2)
                        .foregroundStyle(Palette.blue)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.heroGradient, lineWidth: 1.5)
        )
    }
}

private struct ExplorerScoreBreakdownView: View {
    let score: ExplorerScore

    var body: some View {
        List {
            Section {
                ForEach(score.components) { component in
                    HStack {
                        Text(component.label)
                        Spacer()
                        Text("+\(Int(component.points))")
                            .font(.subheadline.bold())
                            .foregroundStyle(Palette.blue)
                    }
                }
            } header: {
                Text("How the score is calculated")
            } footer: {
                Text("An open formula, not a black box — variety (countries, different modes of transport) counts more than raw distance.")
            }
            Section {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(score.total).formatted()) \(L("pts"))")
                        .font(.headline)
                        .foregroundStyle(Palette.blue)
                }
            }
        }
        .navigationTitle("Explorer Score")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lista po tapnięciu odznaki (poza "Around the World", która nie jest
/// klikalna — to pojedynczy zbiorczy mnożnik, nie lista pozycji) — user
/// 30.07.2026: "klikamy kraje wyświetla się lista krajów, klikamy miasta
/// lista miast itd". Te same, już policzone `detailRows` co pasek postępu
/// na karcie, więc liczby zawsze się zgadzają.
private struct AchievementDetailListView: View {
    let achievement: Achievement

    var body: some View {
        Group {
            if achievement.detailRows.isEmpty {
                VStack(spacing: 8) {
                    Text(achievement.emoji)
                        .font(.system(size: 40))
                        .opacity(0.4)
                    Text("Nothing here yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(achievement.detailRows) { row in
                    HStack {
                        Text(row.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if let subtitle = row.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let trailing = row.trailing {
                            Text(trailing)
                                .font(.subheadline.bold())
                                .foregroundStyle(Palette.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle(achievement.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pełnej szerokości, wyróżniony wiersz dla Kraje/Miasta/Loty — user
/// 30.07.2026: te trzy mają prowadzić wzrok bardziej niż środki transportu.
/// Ten sam format co `AroundTheWorldCard` (żeby wizualnie należały do tej
/// samej "wagi"), tylko mniejszy i klikalny.
private struct FeaturedAchievementCard: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.emoji)
                .font(.system(size: 30))
                .opacity(achievement.isUnlocked ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.title)
                        .font(.headline)
                    if let tier = achievement.currentTierName {
                        Text(tier)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Palette.heroGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(achievement.isUnlocked ? achievement.formatted(achievement.currentValue) : L("Ready to unlock"))
                    .font(.title3.bold())
                    .foregroundStyle(achievement.isUnlocked ? Palette.blue : .secondary)
                if let message = achievement.progressMessage {
                    ProgressView(value: achievement.progressToNext)
                        .tint(Palette.blue)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if achievement.isUnlocked {
                    Text("Max level")
                        .font(.caption2)
                        .foregroundStyle(Palette.blue)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(achievement.isUnlocked ? Palette.heroGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), lineWidth: achievement.isUnlocked ? 1.5 : 0)
        )
    }
}

/// Wspólny styl wiersza-wejścia do dodatkowych ekranów (Travel Passport,
/// Travel Wrapped) pod hero-kafelkami — jeden komponent zamiast kopiowania
/// tego samego HStacka.
private struct SecondaryLinkRow: View {
    let emoji: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 22))
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AchievementCard: View {
    let achievement: Achievement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(achievement.emoji)
                    .font(.system(size: 32))
                    .opacity(achievement.isUnlocked ? 1 : 0.35)
                Spacer()
                if let tier = achievement.currentTierName {
                    Text(tier)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.heroGradient, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            Text(achievement.title)
                .font(.subheadline.bold())
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

            // Zawsze prawdziwa aktualna wartość, NIE ostatni zdobyty próg —
            // user 30.07.2026: pokazywanie progu ("Kraje 5" przy 5 progach
            // 1/5/10/25/50) myliło się z aktualną liczbą, zwłaszcza gdy user
            // nie trafił dokładnie w próg (np. 13 miast przy progu 5 → górna
            // liczba pokazywała "5", dolna "13/15" — wyglądało jak błąd).
            Text(achievement.isUnlocked ? achievement.formatted(achievement.currentValue) : L("Ready to unlock"))
                .font(.caption.bold())
                .foregroundStyle(achievement.isUnlocked ? Palette.blue : .secondary)

            if let message = achievement.progressMessage {
                ProgressView(value: achievement.progressToNext)
                    .tint(Palette.blue)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Max level")
                    .font(.caption2)
                    .foregroundStyle(Palette.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(achievement.isUnlocked ? Palette.heroGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), lineWidth: achievement.isUnlocked ? 1.5 : 0)
        )
    }
}

/// Karta ukrytej odznaki (13.08.2026) — TYLKO odblokowana wersja istnieje
/// (patrz `AchievementsView.body`, sekcja renderuje się wyłącznie gdy
/// `hiddenBadges` nie jest puste), więc świadomie bez szarej/zablokowanej
/// wersji jak `AchievementCard` — nie ma "do zdobycia" dla czegoś co jest
/// niespodzianką.
private struct HiddenBadgeCard: View {
    let badge: HiddenBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(badge.emoji)
                .font(.system(size: 32))
            Text(badge.title)
                .font(.subheadline.bold())
            Text(badge.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.heroGradient, lineWidth: 1.5)
        )
    }
}
