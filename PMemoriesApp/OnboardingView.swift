import SwiftUI
import SwiftData
import AuthenticationServices

/// Szybki samouczek przy pierwszym uruchomieniu appki — UI.md, dopisane
/// 30.07.2026 przez usera. Pokazuje się raz (flaga w UserDefaults), potem
/// nigdy więcej — można go pominąć w każdej chwili.
enum OnboardingStorage {
    private static let key = "hasCompletedOnboarding"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let subtitle: String
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var pageIndex = 0
    // Sign in with Apple przeniesione TU, na koniec onboardingu (08.08.2026,
    // user: "po zalogowaniu się przez Apple na samym początku, nie tylko w
    // rankingu") — wcześniej appka pytała o nazwę TYLKO gdy user sam wszedł
    // do Rankingu, więc dla większości userów `AuthManager.displayName`
    // zostawało `nil` na zawsze, a powitanie na Home nie miało skąd wziąć
    // imienia.
    // WYMAGANE od 12.08.2026 (user: "każdy przy starcie apki pierwszy raz
    // się musi zalogować") — REWIZJA wcześniejszej decyzji z 08.08.2026
    // (był świadomie pomijalny). Powód zmiany: user zauważył że po ponad
    // tygodniu testów w rankingu wciąż widać tylko jedną osobę — logowanie
    // dalej dało się pominąć (ten sam przycisk "Skip" co reszta
    // onboardingu kończył cały proces, nie tylko tę stronę), więc
    // większość testerów nigdy nie trafiała do publicznej bazy CloudKit.
    @StateObject private var auth = AuthManager.shared
    @State private var authErrorMessage: String?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @Query private var savedProjects: [SavedProject]

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                symbol: "sparkles",
                title: L("Welcome to PMemories"),
                subtitle: L("Turn your photos and videos into a movie, set to music, in a few taps.")
            ),
            OnboardingPage(
                symbol: "wand.and.stars",
                title: L("Create Memory"),
                // Rozszerzone 02.08.2026 (user: "czy dokladnie tlumaczy ze
                // jak dodamy utwor to zdjecia/wideo bedzie dopasowane na
                // dlugosc utworu?") — poprzednia wersja tego NIE mówiła
                // wprost, mimo że to kluczowy, nieoczywisty dla nowych
                // testerów mechanizm.
                subtitle: L("Pick photos and videos — PMemories builds a first cut automatically. Add a song and everything adjusts to match its length, ready for you to fine-tune.")
            ),
            OnboardingPage(
                symbol: "map",
                title: L("Travel Map"),
                subtitle: L("Track your trips on an animated map and turn your route into a cinematic video.")
            ),
            OnboardingPage(
                symbol: "film.stack",
                title: L("Studio & Library"),
                subtitle: L("Edit transitions, captions and music in Studio, then find every finished movie in your Library.")
            )
        ]
    }

    var body: some View {
        ZStack {
            Palette.heroGradient.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    // "Skip" pomija TYLKO strony z opisem funkcji, nie
                    // logowanie (12.08.2026) — ląduje na stronie logowania
                    // zamiast od razu kończyć cały onboarding, żeby
                    // logowanie zostało wymagane niezależnie od tego czy
                    // user przeszedł przez wszystkie strony po kolei.
                    if pageIndex < pages.count {
                        Button(L("Skip")) { withAnimation { pageIndex = pages.count } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: page.symbol)
                                .font(.system(size: 64))
                                .foregroundStyle(Palette.heroGradient)
                            Text(page.title)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                            Text(page.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)
                            Spacer()
                            Spacer()
                        }
                        .tag(index)
                    }
                    signInPage
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                // Na stronie logowania ZNIKA dopóki user się nie zaloguje
                // (12.08.2026) — `SignInWithAppleButton` jest wtedy jedyną
                // dostępną akcją, nic już nie pozwala "przejść dalej" bez
                // logowania.
                if pageIndex < pages.count || auth.isSignedIn {
                    Button {
                        if pageIndex < pages.count {
                            withAnimation { pageIndex += 1 }
                        } else {
                            finish()
                        }
                    } label: {
                        Text(pageIndex < pages.count ? L("Next") : L("Get Started"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Palette.heroGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var signInPage: some View {
        VStack(spacing: 20) {
            Spacer()
            if auth.isSignedIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.heroGradient)
                Text(L("You're all set"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                if let name = auth.displayName {
                    Text("\(L("Signed in as")) \(name)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            } else {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.heroGradient)
                Text(L("Personalize PMemories"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(L("Sign in with Apple so PMemories can greet you by name and let you join the tester Ranking."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 46)
                .padding(.horizontal, 40)

                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            Spacer()
            Spacer()
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        do {
            try auth.handle(result: result)
            authErrorMessage = nil
            submitScoreIfSignedIn()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    /// Wysyła wynik do rankingu OD RAZU po zalogowaniu (12.08.2026, user:
    /// "wysyłaj wynik po zalogowaniu, bez potrzeby wchodzenia w Ranking") —
    /// wcześniej `LeaderboardService.submitCurrentScore` był wołany
    /// WYŁĄCZNIE z `LeaderboardView.refresh()`, więc user zalogowany tu, w
    /// onboardingu, nigdy nie trafiał do publicznej bazy dopóki sam nie
    /// otworzył zakładki Ranking. Zero nowego liczenia wyniku — ten sam
    /// `TravelAchievementsCalculator.explorerScore` co `LeaderboardView`.
    /// Świadomie "fire and forget" (`try?`) — brak sieci/CloudKit tutaj nie
    /// powinien przerwać onboardingu, appka spróbuje ponownie przy
    /// pierwszej wizycie w Ranking.
    private func submitScoreIfSignedIn() {
        guard auth.isSignedIn else { return }
        let score = TravelAchievementsCalculator.explorerScore(from: savedTrips, projects: savedProjects)
        Task {
            let avatarFrame = UserDefaults.standard.string(forKey: "selectedAvatarFrame") ?? AvatarFrame.none.rawValue
            try? await LeaderboardService.submitCurrentScore(
                score: score, km: score.totalKm, countries: score.rawCountries,
                cities: score.rawCities, elevationM: score.rawElevationM, avatarFrame: avatarFrame
            )
        }
    }

    private func finish() {
        OnboardingStorage.markCompleted()
        onFinish()
    }
}
