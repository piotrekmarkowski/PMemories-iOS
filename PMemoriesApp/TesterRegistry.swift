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
enum TesterRegistry {
    static let knownTesterIdentifiers: Set<String> = [
        "001384.84ab02a1e28f4a718aa7255a4552d508.1108", // Piotr (założyciel)
        "001771.1a4734051ea84c2b95b94da24aa0d519.1026", // Alexandra
    ]

    static func isTester(_ userIdentifier: String?) -> Bool {
        guard let userIdentifier else { return false }
        return knownTesterIdentifiers.contains(userIdentifier)
    }
}
