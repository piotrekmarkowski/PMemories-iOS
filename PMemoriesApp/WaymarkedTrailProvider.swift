import Foundation
import CoreLocation

/// Szuka realnych, NAZWANYCH szlaków pieszych (OpenStreetMap `route=hiking`,
/// ta sama baza danych co Waymarked Trails, https://waymarkedtrails.org) w
/// okolicy odcinka Wędrówki, zamiast zawsze polegać na zwykłych trasach
/// pieszych po drogach z `MKDirections(.walking)`.
///
/// Overpass API (`overpass-api.de`) to surowa baza danych OSM, NIE silnik
/// routingu — potrafi odpowiedzieć "jakie szlaki są w tej okolicy", nie
/// "policz mi trasę między dwoma dowolnymi punktami po szlakach" (to
/// wymagałoby płatnego/kluczowanego serwisu jak openrouteservice — świadomie
/// POZA zakresem, wymaga decyzji usera o założeniu konta). Dlatego: gdy
/// znajdzie się prawdziwy, nazwany szlak, którego geometria przechodzi
/// blisko OBU końców odcinka, używamy JEGO prawdziwej trasy — w przeciwnym
/// razie `RouteProvider` cicho wraca do dotychczasowego `.walking`
/// (`RouteProvider.route`, `.hiking` case) — zero regresji.
enum WaymarkedTrailProvider {
    private static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    /// Realny szlak nie zaczyna/kończy się dokładnie na wskazanym pinie
    /// (geokodowanie miasta/miejsca to przybliżenie) — akceptujemy dopasowanie
    /// gdy oba końce leżą w tej odległości od linii szlaku.
    private static let matchThresholdMeters: Double = 300

    static func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteResult? {
        let straightLine = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        // Promień wyszukiwania proporcjonalny do długości odcinka (żeby nie
        // ściągać danych z połowy regionu przy krótkiej wędrówce), z sensownym
        // minimum i górnym ograniczeniem (unikamy zbyt ciężkiego zapytania).
        let radius = min(20_000, max(2_000, straightLine * 1.5))
        let midLat = (from.latitude + to.latitude) / 2
        let midLon = (from.longitude + to.longitude) / 2

        let query = """
        [out:json][timeout:8];
        relation["route"="hiking"](around:\(Int(radius)),\(midLat),\(midLon));
        out geom;
        """

        guard let candidates = try? await fetchCandidates(query: query) else { return nil }

        var best: (path: [CLLocationCoordinate2D], length: Double)?
        for candidate in candidates {
            guard candidate.count >= 2,
                  let match = matchedSubsegment(in: candidate, from: from, to: to) else { continue }
            if best == nil || match.length < best!.length {
                best = match
            }
        }
        guard let best else { return nil }
        // Overpass nie zwraca czasu przejścia szlaku — estymowany z tempa
        // marszowego (18.08.2026, `RouteProvider.estimatedSpeedKmh`), ten
        // sam placeholder co reszta fallbacków bez realnego API czasu.
        let distanceKm = best.length / 1000
        let durationMinutes = distanceKm / RouteProvider.estimatedSpeedKmh(for: .hiking) * 60
        return RouteResult(path: best.path, distanceKm: distanceKm, durationMinutes: durationMinutes)
    }

    /// Pobiera i parsuje odpowiedź Overpass do listy kandydackich polilinii —
    /// jedna na relację `route=hiking`, złożona z geometrii wszystkich jej
    /// segmentów-dróg w kolejności zwróconej przez Overpass (`out geom`
    /// rozwiązuje współrzędne od razu, bez drugiego zapytania o same węzły).
    private static func fetchCandidates(query: String) async throws -> [[CLLocationCoordinate2D]] {
        // Overpass akceptuje surowe zapytanie WPROST jako ciało POST (bez
        // prefiksu "data=" i bez url-encodingu) — prostsze i bez ryzyka
        // błędnego kodowania znaków specjalnych zapytania (`[`, `;`, itd.)
        // które by wystąpiło przy budowaniu formularza `x-www-form-urlencoded`.
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = query.data(using: .utf8)
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

        return response.elements.compactMap { element in
            guard let members = element.members else { return nil }
            let coordinates = members.flatMap { member in
                (member.geometry ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            }
            return coordinates.isEmpty ? nil : coordinates
        }
    }

    /// Sprawdza czy `candidate` przechodzi blisko OBU punktów (`from`/`to`) —
    /// jeśli tak, wycina fragment MIĘDZY najbliższymi punktami (w dowolnej
    /// kolejności — dopasowany indeks `from` może wypaść dalej na linii niż
    /// `to`, jeśli szlak biegnie "w drugą stronę" niż kierunek podróży) i
    /// liczy jego prawdziwą długość sumując odległości kolejnych punktów.
    private static func matchedSubsegment(
        in candidate: [CLLocationCoordinate2D], from: CLLocationCoordinate2D, to: CLLocationCoordinate2D
    ) -> (path: [CLLocationCoordinate2D], length: Double)? {
        guard let fromMatch = closestIndex(in: candidate, to: from),
              let toMatch = closestIndex(in: candidate, to: to),
              fromMatch.distance <= matchThresholdMeters,
              toMatch.distance <= matchThresholdMeters,
              fromMatch.index != toMatch.index else { return nil }

        let lowerIndex = min(fromMatch.index, toMatch.index)
        let upperIndex = max(fromMatch.index, toMatch.index)
        var subsegment = Array(candidate[lowerIndex...upperIndex])
        // Szlak mógł biec w przeciwną stronę względem kierunku podróży —
        // odwracamy tak, żeby zawsze zaczynał się bliżej `from`.
        if fromMatch.index > toMatch.index {
            subsegment.reverse()
        }

        var length: Double = 0
        for i in 1..<subsegment.count {
            length += CLLocation(latitude: subsegment[i - 1].latitude, longitude: subsegment[i - 1].longitude)
                .distance(from: CLLocation(latitude: subsegment[i].latitude, longitude: subsegment[i].longitude))
        }
        return (subsegment, length)
    }

    private static func closestIndex(
        in path: [CLLocationCoordinate2D], to target: CLLocationCoordinate2D
    ) -> (index: Int, distance: Double)? {
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        var best: (index: Int, distance: Double)?
        for (index, coordinate) in path.enumerated() {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: targetLocation)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best
    }
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let members: [OverpassMember]?
}

private struct OverpassMember: Decodable {
    let geometry: [OverpassGeometryPoint]?
}

private struct OverpassGeometryPoint: Decodable {
    let lat: Double
    let lon: Double
}
