import Foundation
import SwiftData
import CoreLocation

/// Automatyczne dopasowanie gotowego Memory do przystanku ZAPLANOWANEJ
/// podróży (30.08.2026) — user: "trase robimy wczesniej zanim gdzies
/// polecimy wiec nie ma sensu dodawac zdjec czy czegos tego typu podczas
/// jej tworzenia". Appka już dziś zna lokalizację/datę KAŻDEGO zdjęcia (ten
/// sam mechanizm co Smart Route, `MediaAssetLoader.locationsAndDates`) —
/// zero potrzeby na prawdziwe AI/model językowy, to zwykłe dopasowanie
/// geograficzne, dokładnie tak samo deterministyczne jak wykrywanie tras.
enum TripMemoryMatcher {
    struct Suggestion {
        let trip: SavedTrip
        let stop: SavedStop
    }

    /// TEN SAM promień co `WorldGlobeView.clusterRadiusKm` — spójne "to samo
    /// miejsce" w całej appce, nie osobna, niezależnie dobrana wartość.
    private static let matchRadiusKm: Double = 20

    /// Najbliższy nieprzypisany przystanek spośród WSZYSTKICH zapisanych
    /// podróży, w promieniu `matchRadiusKm` od którejkolwiek lokalizacji
    /// zdjęcia w projekcie — `nil` gdy żadne zdjęcie nie ma GPS, albo żaden
    /// przystanek nie leży wystarczająco blisko. Przystanki JUŻ powiązane z
    /// jakimkolwiek filmem pomijane — appka nigdy nie nadpisuje istniejącego,
    /// ręcznie ustawionego linku (ten sam duch co "Link to a Movie" w
    /// `TravelMapView`, świadomie zawsze ręczne/potwierdzane, nigdy ciche).
    static func bestMatch(for project: SavedProject, trips: [SavedTrip]) -> Suggestion? {
        let identifiers = project.items.map(\.assetLocalIdentifier).filter { !$0.isEmpty }
        guard !identifiers.isEmpty else { return nil }
        let locations = MediaAssetLoader.locationsAndDates(forAssetLocalIdentifiers: identifiers)
        guard !locations.isEmpty else { return nil }

        var best: (stop: SavedStop, trip: SavedTrip, distanceKm: Double)?
        for trip in trips {
            for stop in trip.stops where stop.linkedProjectID == nil {
                for entry in locations {
                    let distance = RouteProvider.straightDistanceKm(from: stop.coordinate, to: entry.location.coordinate)
                    guard distance <= matchRadiusKm else { continue }
                    if best == nil || distance < best!.distanceKm {
                        best = (stop, trip, distance)
                    }
                }
            }
        }
        guard let best else { return nil }
        return Suggestion(trip: best.trip, stop: best.stop)
    }
}
