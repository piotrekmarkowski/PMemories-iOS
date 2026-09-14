import CoreLocation
import Foundation

/// Automatyczne rozpoznawanie szczytu górskiego przez GPS — user: "wejdę na
/// Rysy, włączę appkę i appka automatycznie z użyciem GPS-a wyłapie gdzie
/// jestem, jaki to szczyt, i zapisze" (`Docs/Travel.md`, 29.07.2026). Inny
/// mechanizm niż trasowanie Wędrówki (które celowo NIE używa GPS-a, żeby nie
/// zużywać baterii) — to JEDNORAZOWA, świadoma akcja usera (przycisk w
/// formularzu przystanku), nie śledzenie lokalizacji w tle. Ta sama rodzina
/// API co `WaymarkedTrailProvider` (Overpass, dane OpenStreetMap, bez konta).
enum PeakDetector {
    enum PeakDetectorError: LocalizedError {
        case permissionDenied
        case noPeakNearby

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "No location access — enable it in Settings so the app can recognize the peak."
            case .noPeakNearby: return "No peak found in the OpenStreetMap database within 1 km."
            }
        }
    }

    struct DetectedPeak {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let country: String?
        let countryCode: String?
    }

    /// GPS w górach bywa mniej dokładne (odbicia od skał) niż na otwartym
    /// terenie — szerszy promień niż standardowy próg dopasowania trasy w
    /// `WaymarkedTrailProvider`.
    private static let searchRadiusMeters: Double = 1000

    static func detectNearbyPeak() async throws -> DetectedPeak {
        let location = try await CurrentLocationProvider.currentLocation()
        guard let match = try await nearestPeak(near: location.coordinate) else {
            throw PeakDetectorError.noPeakNearby
        }
        let (country, countryCode) = await resolveCountry(for: match.coordinate)
        return DetectedPeak(name: match.name, coordinate: match.coordinate, country: country, countryCode: countryCode)
    }

    /// Wyszukiwanie szczytu PO NAZWIE, bez wymogu stania na nim z włączonym
    /// GPS-em (09.09.2026, user: "nie mozna wybrac na liscie szczytow jesli
    /// sie chodzi po gorach... dzien pozniej sie chce stworzyc mape albo po
    /// wyprawie nie mozna wybrac gdzie sie bylo" — `detectNearbyPeak` działa
    /// TYLKO w momencie stania na szczycie, więc dobudowanie trasy później
    /// albo z domu było niemożliwe).
    ///
    /// UWAGA: pierwsza wersja próbowała tego samego zapytania Overpass co
    /// `nearestPeak` (`node["natural"="peak"]["name"~...]`), tylko bez
    /// promienia `around:` — user zgłosił "szczyty się nie wyszukują".
    /// Przyczyna sprawdzona bezpośrednio (`curl` do publicznego Overpass):
    /// `"remark": "runtime error: Query timed out"` — wyszukiwanie PO
    /// NAZWIE bez ograniczenia geograficznego to skan CAŁEJ planety (Overpass
    /// ma indeks przestrzenny, nie tekstowy), publiczny serwer zawsze się na
    /// tym wykłada. Zamiast tego Nominatim (ten sam ekosystem OSM, ale
    /// zaprojektowany do wyszukiwania PO NAZWIE — ma własny indeks
    /// tekstowy) — filtrowane do `class=natural`/`type=peak`, żeby nie
    /// mieszać z miastami/restauracjami o tej samej nazwie. Kraj/kod kraju
    /// od razu w odpowiedzi (`address`), bez osobnego reverse-geocode.
    static func searchPeaks(named query: String) async throws -> [DetectedPeak] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let url = URL(string: "https://nominatim.openstreetmap.org/search?q=\(encoded)&format=json&limit=15&addressdetails=1")!

        var request = URLRequest(url: url)
        // Nominatim usage policy wymaga rozpoznawalnego User-Agent —
        // anonimowe/domyślne żądania bywają odrzucane/throttlowane.
        request.setValue("PMemories iOS App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let results = try JSONDecoder().decode([NominatimResult].self, from: data)

        return results
            .filter { $0.category == "natural" && $0.type == "peak" }
            .compactMap { result -> DetectedPeak? in
                guard let name = result.name ?? result.address?.peak,
                      let lat = Double(result.lat), let lon = Double(result.lon) else { return nil }
                return DetectedPeak(
                    name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    country: result.address?.country, countryCode: result.address?.countryCode?.uppercased()
                )
            }
    }

    /// Współrzędna SZCZYTU (węzeł OSM), nie surowa (mniej dokładna) pozycja
    /// GPS usera — precyzyjniejsze i od razu w pełni rozwiązuje przystanek
    /// (`TripStop.coordinate` ustawione), bez pośredniego kroku wyboru
    /// podpowiedzi z `CitySearchCompleter`, który mógłby nie odnaleźć
    /// odległej/rzadko wyszukiwanej nazwy szczytu.
    private static func resolveCountry(for coordinate: CLLocationCoordinate2D) async -> (country: String?, countryCode: String?) {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ).first
        return (placemark?.country, placemark?.isoCountryCode)
    }

    private static func nearestPeak(near coordinate: CLLocationCoordinate2D) async throws -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let query = """
        [out:json][timeout:8];
        node["natural"="peak"](around:\(Int(searchRadiusMeters)),\(coordinate.latitude),\(coordinate.longitude));
        out;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.httpBody = query.data(using: .utf8)
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OverpassPeakResponse.self, from: data)

        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let named = response.elements.compactMap { element -> (name: String, coordinate: CLLocationCoordinate2D, distance: Double)? in
            guard let name = element.tags?.name else { return nil }
            let peakCoordinate = CLLocationCoordinate2D(latitude: element.lat, longitude: element.lon)
            let distance = CLLocation(latitude: element.lat, longitude: element.lon).distance(from: target)
            return (name, peakCoordinate, distance)
        }
        guard let closest = named.min(by: { $0.distance < $1.distance }) else { return nil }
        return (closest.name, closest.coordinate)
    }
}

private struct OverpassPeakResponse: Decodable {
    let elements: [OverpassPeakElement]
}

private struct OverpassPeakElement: Decodable {
    let lat: Double
    let lon: Double
    let tags: OverpassPeakTags?
}

private struct OverpassPeakTags: Decodable {
    let name: String?
}

private struct NominatimResult: Decodable {
    let name: String?
    let lat: String
    let lon: String
    let category: String
    let type: String
    let address: NominatimAddress?

    enum CodingKeys: String, CodingKey {
        case name, lat, lon, type, address
        case category = "class"
    }
}

private struct NominatimAddress: Decodable {
    let peak: String?
    let country: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case peak, country
        case countryCode = "country_code"
    }
}

/// Most między delegate-owym `CLLocationManager` a `async`/`await` — JEDNO,
/// jednorazowe żądanie lokalizacji (`requestLocation()`), nie ciągłe
/// śledzenie. Reszta Travel Map (trasowanie, geokodowanie miast) celowo
/// działa bez lokalizacji usera, żeby nie zużywać baterii — to i
/// `TravelJourneyPosterView` (13.09.2026, wschód/zachód słońca pod
/// dzień/noc mapy plakatu) to jedyne dwa świadome, JEDNORAZOWE użycia GPS-a
/// w całej appce. Stąd `internal` zamiast `private` — współdzielone, nie
/// duplikowane.
@MainActor
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case permissionDenied
        case failed(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "No location access — enable it in Settings so the app can recognize the peak."
            case .failed(let error): return error.localizedDescription
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    static func currentLocation() async throws -> CLLocation {
        let provider = CurrentLocationProvider()
        return try await provider.request()
    }

    private func request() async throws -> CLLocation {
        manager.delegate = self
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw LocationError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.continuation?.resume(throwing: LocationError.permissionDenied)
                self.continuation = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.continuation?.resume(returning: location)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: LocationError.failed(error))
            self.continuation = nil
        }
    }
}
