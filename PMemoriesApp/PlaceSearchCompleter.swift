import MapKit
import CoreLocation
import Combine

/// Podpowiedzi PUNKTÓW ZAINTERESOWANIA (zabytki, muzea, restauracje...) przy
/// wpisywaniu "Places to visit" w Trip Planning (18.08.2026, user: "żeby
/// miało podpowiedzi tak jak przy mieście/lotnisku"). Osobna klasa od
/// `CitySearchCompleter` (nie rozszerzenie/reużycie) — inny filtr wyników
/// (WSZYSTKIE punkty zainteresowania, nie tylko lotniska; bez adresów
/// ulicznych, "miejsce do zobaczenia" to prawie zawsze POI, nie adres) i
/// inne przeznaczenie wyniku: `CitySearchCompleter.resolve()` rozwiązuje
/// współrzędną/kraj (mapa/pineska), tu wystarczy sam POPRAWNY TEKST nazwy —
/// `PlaceToVisit` nie przechowuje współrzędnych.
@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest]
    }

    /// Obszar wyszukiwania wyśrodkowany na mieście TEGO przystanku (18.08.2026)
    /// — bez tego `MKLocalSearchCompleter` szuka po całym świecie, "Louvre"
    /// wpisane przy przystanku w Paryżu powinno faworyzować paryski Luwr, nie
    /// przypadkowy wynik gdzie indziej. Promień ~50km, wystarczający dla
    /// miasta i najbliższej okolicy.
    func setRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }

    func updateQuery(_ query: String) {
        completer.queryFragment = query
    }

    func clear() {
        completer.queryFragment = ""
        results = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = completer.results
        Task { @MainActor in
            self.results = newResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
