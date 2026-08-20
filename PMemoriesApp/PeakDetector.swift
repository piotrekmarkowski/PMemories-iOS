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
        // Współrzędna SZCZYTU (węzeł OSM), nie surowa (mniej dokładna) pozycja
        // GPS usera — precyzyjniejsze i od razu w pełni rozwiązuje przystanek
        // (`TripStop.coordinate` ustawione), bez pośredniego kroku wyboru
        // podpowiedzi z `CitySearchCompleter`, który mógłby nie odnaleźć
        // odległej/rzadko wyszukiwanej nazwy szczytu.
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: match.coordinate.latitude, longitude: match.coordinate.longitude)
        ).first
        return DetectedPeak(
            name: match.name, coordinate: match.coordinate,
            country: placemark?.country, countryCode: placemark?.isoCountryCode
        )
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

/// Most między delegate-owym `CLLocationManager` a `async`/`await` — JEDNO,
/// jednorazowe żądanie lokalizacji (`requestLocation()`), nie ciągłe
/// śledzenie. Świadomie jedyne miejsce w appce sięgające po GPS — reszta
/// Travel Map (trasowanie, geokodowanie miast) celowo działa bez lokalizacji
/// usera, żeby nie zużywać baterii.
@MainActor
private final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
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
