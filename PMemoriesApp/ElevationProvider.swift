import Foundation
import CoreLocation

/// Statystyki wysokości dla odcinka Wędrówki (przewyższenie, najwyższy
/// punkt) — user: "pasuje pokrycie na całym świecie łącznie z wysokościami,
/// żeby mieć też w statystykach jak wysoko się było" (`Docs/Travel.md`,
/// 29.07.2026). Open-Meteo Elevation API — darmowe, bez konta/klucza dla
/// użytku niekomercyjnego (ten sam wzorzec "brak własnego serwera" co
/// `MKDirections`/`CLGeocoder`/`WaymarkedTrailProvider`), globalne pokrycie.
enum ElevationProvider {
    private static let endpoint = "https://api.open-meteo.com/v1/elevation"
    /// Limit API (do 100 współrzędnych na zapytanie) — ścieżka jest
    /// dociągana do co najwyżej tylu punktów PRZED zapytaniem, ta sama
    /// technika interpolacji liniowej co `RouteProvider.resamplePath`
    /// (wystarczająca rozdzielczość do policzenia sumy podejść/najwyższego
    /// punktu, nie potrzeba każdego surowego punktu trasy).
    private static let maxPoints = 100

    /// `nil` gdy zapytanie się nie powiedzie (offline, timeout, błąd
    /// serwera) — wywołujący ma wtedy po prostu nie zapisywać statystyk dla
    /// tego odcinka, nie przerywać całego zapisu trasy.
    static func profile(for path: [CLLocationCoordinate2D]) async -> (gainMeters: Double, highestMeters: Double)? {
        guard path.count >= 2 else { return nil }
        let sampled = RouteProvider.resamplePath(path, targetCount: min(maxPoints, path.count))

        let lats = sampled.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")
        let lons = sampled.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")
        guard let url = URL(string: "\(endpoint)?latitude=\(lats)&longitude=\(lons)") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ElevationResponse.self, from: data),
              response.elevation.count == sampled.count else { return nil }

        var gain: Double = 0
        var highest = response.elevation.first ?? 0
        for i in 1..<response.elevation.count {
            let delta = response.elevation[i] - response.elevation[i - 1]
            if delta > 0 { gain += delta }
            highest = max(highest, response.elevation[i])
        }
        return (gainMeters: gain, highestMeters: highest)
    }
}

private struct ElevationResponse: Decodable {
    let elevation: [Double]
}
