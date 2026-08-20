import CoreLocation

/// Auto-wykrywanie przystanków podróży z GPS+data zdjęć — zamiast ręcznego
/// wpisywania każdego miasta osobno w `TravelMapView`. Proste, JAWNE progi
/// (nie ML/"AI"): promień grupowania w miasto (`clusterRadiusKm`) i próg
/// dystansu samolot/samochód (`flightDistanceThresholdKm`). Transport to
/// tylko wstępna zgadywanka między dwiema opcjami — pociąg/prom/rejs/
/// wędrówka nigdy nie są zgadywane (brak wiarygodnego sygnału w samym
/// GPS+czasie). User i tak przegląda/poprawia każdy wygenerowany przystanek
/// w istniejącym ekranie ręcznej edycji przed zapisaniem trasy — to szybki
/// punkt startowy, nie czarna skrzynka.
enum SmartRouteDetector {
    private static let clusterRadiusKm: Double = 20
    private static let flightDistanceThresholdKm: Double = 300

    static func detectStops(from identifiers: [String]) async -> [TripStop] {
        let points = MediaAssetLoader.locationsAndDates(forAssetLocalIdentifiers: identifiers)
        let dated: [(identifier: String, location: CLLocation, date: Date)] = points.compactMap { point in
            guard let date = point.date else { return nil }
            return (point.identifier, point.location, date)
        }.sorted { $0.date < $1.date }
        guard !dated.isEmpty else { return [] }

        // Zachłanne grupowanie sekwencyjne po BIEŻĄCYM centroidzie klastra
        // (nie po stałym pierwszym punkcie) — unika driftu przy kilkudniowym
        // pobycie z wędrówkami po całym mieście.
        //
        // Sprawdza WSZYSTKIE dotychczasowe klastry, nie tylko ostatni
        // (poprawka 10.08.2026, TODO.md P2 — "sprawdzić czy auto-detekcja
        // radzi sobie z bałaganem... wiele krótkich przystanków"). Bez tego
        // typowy wzorzec "baza + wycieczka jednodniowa + powrót do bazy"
        // (np. Rzym → Tivoli → Rzym) tworzył TRZY osobne przystanki zamiast
        // dwóch — powrót do bazy nie łączył się z JEJ pierwotnym klastrem,
        // bo porównywany był wyłącznie z ostatnim (Tivoli). Realny bałagan w
        // wygenerowanej trasie, który user i tak musiałby ręcznie sprzątać.
        var clusters: [[(identifier: String, location: CLLocation, date: Date)]] = []
        for point in dated {
            var bestMatchIndex: Int?
            var bestMatchDistance = Double.greatestFiniteMagnitude
            for index in clusters.indices {
                let current = clusters[index]
                let avgLat = current.map { $0.location.coordinate.latitude }.reduce(0, +) / Double(current.count)
                let avgLon = current.map { $0.location.coordinate.longitude }.reduce(0, +) / Double(current.count)
                let centroid = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
                let distance = RouteProvider.straightDistanceKm(from: centroid, to: point.location.coordinate)
                if distance <= clusterRadiusKm, distance < bestMatchDistance {
                    bestMatchDistance = distance
                    bestMatchIndex = index
                }
            }
            if let bestMatchIndex {
                clusters[bestMatchIndex].append(point)
            } else {
                clusters.append([point])
            }
        }

        var tripStops: [TripStop] = []
        var previousCentroid: CLLocationCoordinate2D?
        for cluster in clusters {
            let avgLat = cluster.map { $0.location.coordinate.latitude }.reduce(0, +) / Double(cluster.count)
            let avgLon = cluster.map { $0.location.coordinate.longitude }.reduce(0, +) / Double(cluster.count)
            let centroid = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            guard let resolved = await CityGeocoder.reverseResolveFull(CLLocation(latitude: avgLat, longitude: avgLon)) else {
                continue
            }

            // Chronologicznie pierwsze zdjęcie klastra reprezentuje przystanek
            // na markerze — to samo zdjęcie, które już wyznacza `arrivalDate`
            // poniżej, więc oba pola pokazują tę samą, spójną chwilę.
            let earliestPhoto = cluster.min { $0.date < $1.date }

            var stop = TripStop()
            stop.cityName = resolved.city
            stop.coordinate = centroid
            stop.country = resolved.country
            stop.countryCode = resolved.countryCode
            stop.arrivalDate = earliestPhoto?.date
            stop.representativePhotoIdentifier = earliestPhoto?.identifier
            if let previousCentroid {
                let distanceKm = RouteProvider.straightDistanceKm(from: previousCentroid, to: centroid)
                stop.transport = distanceKm > flightDistanceThresholdKm ? .plane : .car
            }
            previousCentroid = centroid
            tripStops.append(stop)
        }
        return tripStops
    }
}
