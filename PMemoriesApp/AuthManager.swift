import AuthenticationServices
import SwiftUI

/// Sign in with Apple — jedyny sposób identyfikacji testera do rankingu
/// (02.08.2026, "ranking na podstawie punktów... żeby sobie porównywać").
/// Bez tego appka nie wiedziałaby CZYJ wynik zapisuje w CloudKit — appka
/// dziś nie ma żadnego konta usera, wszystko jest lokalne (SwiftData na
/// urządzeniu). Zapisany lokalnie identyfikator Apple + wyświetlana nazwa
/// (`UserDefaults`, nie Keychain — to nie sekret/hasło, tylko opaque ID).
///
/// Sam UI przycisku to natywny `SignInWithAppleButton` (SwiftUI, wbudowany
/// w `AuthenticationServices`) — ten manager tylko PRZETWARZA już gotowy
/// wynik z jego `onCompletion`, nie buduje własnego `ASAuthorizationController`
/// (zbędne dublowanie tej samej logiki co przycisk już robi wewnętrznie).
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var userIdentifier: String?
    @Published private(set) var displayName: String?

    private init() {
        userIdentifier = UserDefaults.standard.string(forKey: "appleUserIdentifier")
        // Samo-naprawiające się przycięcie do pierwszego słowa — bez tego
        // ktoś kto już zalogował się PRZED tym fixem (np. user na własnym
        // telefonie: "Piotr Markowski" zamiast "Piotr") zostałby z błędną
        // nazwą na zawsze, dopóki ręcznie by się nie wylogował/zalogował.
        if let stored = UserDefaults.standard.string(forKey: "appleDisplayName"),
           let firstWord = stored.split(separator: " ").first {
            displayName = String(firstWord)
            UserDefaults.standard.set(displayName, forKey: "appleDisplayName")
        } else {
            displayName = nil
        }
    }

    var isSignedIn: Bool { userIdentifier != nil }

    enum AuthError: Error, LocalizedError {
        case invalidCredential

        var errorDescription: String? {
            switch self {
            case .invalidCredential: return L("Sign in with Apple failed. Please try again.")
            }
        }
    }

    func handle(result: Result<ASAuthorization, Error>) throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        var resolvedName = displayName
        // BUG znaleziony 09.08.2026 (user: "dlaczego pojawia się moje pełne
        // imię i nazwisko?") — pole `givenName` z Apple ID może samo w
        // sobie zawierać więcej niż jedno słowo (np. gdy ktoś przy
        // zakładaniu Apple ID wpisał "Piotr Markowski" jako imię, nie
        // rozdzielił na imię/nazwisko) — appka brała całe pole bez
        // podziału. Zawsze tylko PIERWSZE słowo, żeby powitanie zostało
        // krótkie/swobodne niezależnie od tego jak dokładnie ktoś ma
        // skonfigurowane imię w swoim Apple ID.
        if let givenName = credential.fullName?.givenName,
           let firstWord = givenName.split(separator: " ").first, !firstWord.isEmpty {
            resolvedName = String(firstWord)
        }
        // Apple zwraca prawdziwe imię/nazwisko TYLKO przy PIERWSZYM
        // logowaniu na danym urządzeniu — kolejne logowania dają `nil`.
        // Fallback na "Traveler" tylko gdy NIGDY wcześniej nie zapisaliśmy
        // żadnej nazwy (pierwsze logowanie bez podania imienia).
        userIdentifier = credential.user
        displayName = resolvedName ?? L("Traveler")
        UserDefaults.standard.set(userIdentifier, forKey: "appleUserIdentifier")
        UserDefaults.standard.set(displayName, forKey: "appleDisplayName")
    }

    func signOut() {
        userIdentifier = nil
        displayName = nil
        UserDefaults.standard.removeObject(forKey: "appleUserIdentifier")
        UserDefaults.standard.removeObject(forKey: "appleDisplayName")
    }
}
