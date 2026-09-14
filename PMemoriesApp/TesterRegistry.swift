import Foundation

/// Odznaka testera na awatarze (TODO.md 08.08.2026) — appka NIE ma żadnego
/// backendu/członkostwa TestFlight do automatycznego rozpoznania "kto jest
/// testerem" (świadomie, żeby nie budować nowej infrastruktury dla jednej
/// odznaki). Zamiast tego: ręcznie utrzymywana lista stabilnych
/// identyfikatorów Sign in with Apple (`AuthManager.userIdentifier`) —
/// dokładnie ten sam identyfikator co `LeaderboardEntry.recordName` w
/// CloudKit (`LeaderboardService.submitCurrentScore`), więc nowego testera
/// można znaleźć w CloudKit Dashboard/`cktool query-records` po jego
/// pierwszym zalogowaniu się w Rankingu i dopisać tutaj ręcznie.
///
/// Trzy poziomy (28.08.2026, user: "ja mam mieć jedyną w swoim rodzaju [ramkę],
/// testerzy powinni mieć też inny, a reszta będzie bez ramki") — dotąd
/// `isTester` traktowało foundera i testerów jako JEDNĄ kategorię, więc obaj
/// dostawali identyczną ramkę/odznakę. `founder` jest teraz WYŁĄCZONY z
/// `knownTesterIdentifiers` (osobna stała, nie zbiór — jest tylko jeden) i
/// ma własny, unikalny styl w `badge(for:)`; zwykli userzy (spoza obu list)
/// nadal dostają `.none`, bez zmian.
enum TesterRegistry {
    static let founderIdentifier = "001384.84ab02a1e28f4a718aa7255a4552d508.1108" // Piotr

    static let knownTesterIdentifiers: Set<String> = [
        "001771.1a4734051ea84c2b95b94da24aa0d519.1026", // Alexandra
    ]

    enum Badge {
        case none
        case tester
        case founder
    }

    static func badge(for userIdentifier: String?) -> Badge {
        guard let userIdentifier else { return .none }
        if userIdentifier == founderIdentifier { return .founder }
        if knownTesterIdentifiers.contains(userIdentifier) { return .tester }
        return .none
    }

    static func isTester(_ userIdentifier: String?) -> Bool {
        badge(for: userIdentifier) != .none
    }

    /// Premium przejścia (30.08.2026, `TransitionStyle.isPremium`) — appka
    /// nie ma jeszcze płatności, więc "odblokowane" dziś znaczy dosłownie
    /// TYLKO Founder (user: "to bedzie zachowane dla premium i dla mnie") —
    /// świadomie węziej niż `isTester` (Alexandra jako tester NIE dostaje
    /// tego dostępu, to nie jest odznaka tożsamości tylko wczesny dostęp do
    /// płatnej funkcji).
    static func hasPremiumUnlocked(_ userIdentifier: String?) -> Bool {
        badge(for: userIdentifier) == .founder
    }
}
