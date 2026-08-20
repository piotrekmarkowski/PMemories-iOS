import Foundation

/// Bug znaleziony 03.08.2026 (user: trasa LGW → LGW, kilka różnych środków
/// transportu, "czekałem 15 min i się nie zapisała") — `CLGeocoder`
/// (`CityGeocoder.resolve`) i `MKDirections` (`RouteProvider.directionsRoute`)
/// to jedyne dwa zapytania sieciowe w całym pipeline zapisu trasy BEZ
/// żadnego timeoutu (w odróżnieniu od `WaymarkedTrailProvider`/
/// `ElevationProvider`, które mają `request.timeoutInterval = 8` na surowym
/// `URLRequest`) — Apple nie daje takiego parametru na tych dwóch API. Na
/// słabym/przeciążonym WiFi (lotnisko to klasyczny przypadek) request potrafi
/// wisieć bez odpowiedzi i bez błędu, zamrażając `buildRoute()`/`persistTrip`
/// w nieskończoność (spinner "Looking up cities…" nigdy się nie kończy, nic
/// się nie zapisuje, zero komunikatu — myląco wygląda jak appka "nic nie robi").
enum AsyncTimeout {
    struct TimedOut: Error {}

    /// Ściga `operation` z odliczaniem — cokolwiek skończy się pierwsze,
    /// wygrywa. Jeśli `operation` nie zdąży, funkcja i tak ODDAJE STEROWANIE
    /// wołającemu po `seconds` (nawet jeśli system nie zdąży faktycznie
    /// anulować leżącego u podstaw requestu sieciowego) — to wystarczy, żeby
    /// UI/zapis nie zamarzały, reszta kodu już dziś traktuje `nil`/błąd z
    /// tych wywołań jako normalny, spodziewany przypadek (`try?` + fallback).
    static func run<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            guard let result = try await group.next() else { throw TimedOut() }
            group.cancelAll()
            return result
        }
    }
}
