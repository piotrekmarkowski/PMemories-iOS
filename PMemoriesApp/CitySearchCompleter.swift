import MapKit
import CoreLocation
import Combine

/// Podpowiedzi miast i lotnisk podczas wpisywania — `MKLocalSearchCompleter`
/// z filtrem na adresy (miasta) + punkty zainteresowania typu lotnisko.
@MainActor
final class CitySearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
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

    /// Rozwiązuje wybraną podpowiedź do konkretnej współrzędnej — dokładniejsze
    /// niż późniejsze geokodowanie samego tekstu, zwłaszcza dla lotnisk.
    ///
    /// `localizedCityName` (13.08.2026, user: "to powinno być w zależności
    /// od języka jaki mamy ustawiony, a nie ja mam coś zmieniać") —
    /// `MKLocalSearchCompleter` (podpowiedzi podczas wpisywania) ZAWSZE
    /// zwraca tytuł w języku REGIONU TELEFONU (Ustawienia → Region), co
    /// rozjeżdża się z osobnym przełącznikiem języka appki (`AppLanguage`,
    /// Profile → Language) — stąd np. "Londyn" mimo appki po angielsku.
    /// Osobne, DODATKOWE odpytanie `CLGeocoder` z `preferredLocale`
    /// ustawionym na FAKTYCZNY język appki (`Bundle.main.
    /// preferredLocalizations`, ten sam sposób co `isPolishLanguageActive`)
    /// daje nazwę w poprawnym języku niezależnie od regionu telefonu.
    /// `nil` gdy geokodowanie zawiedzie — wołający zostawia wtedy
    /// dotychczasową (surową) nazwę zamiast nadpisywać pustką.
    static func resolve(_ completion: MKLocalSearchCompletion) async -> (coordinate: CLLocationCoordinate2D, country: String?, countryCode: String?, localizedCityName: String?)? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), let item = response.mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        // Lotniska/POI (18.08.2026, user: "Gatwick Airport" zamieniało się
        // w samo Gatwick") — relokalizacja niżej dogeokodowuje `locality`
        // (miejscowość), co ma sens dla MIAST podanych w złym języku, ale
        // dla punktu zainteresowania (lotnisko/POI) to REGRESJA: gubi
        // konkretną nazwę miejsca na rzecz samej miejscowości obok.
        // Pomijana dla POI (`item.pointOfInterestCategory != nil`) — surowy
        // tytuł z podpowiedzi zostaje bez zmian.
        let localizedCityName = item.pointOfInterestCategory == nil ? await localizedCityName(for: coordinate) : nil
        return (coordinate, item.placemark.country, item.placemark.isoCountryCode, localizedCityName)
    }

    /// Nazwa miasta dla ZNANEJ współrzędnej, w języku APPKI — wydzielone z
    /// `resolve()` wyżej, żeby dało się użyć TEGO SAMEGO mechanizmu bez
    /// wcześniejszego wyszukiwania. Reużywane przy imporcie współdzielonej
    /// podróży (13.08.2026, user: "jak ktoś mi wyśle zaproszenie, czy
    /// zapisze się w tym co mam na telefonie?" — dziś importowane nazwy
    /// przychodzą w języku NADAWCY, appka wysyła gotowy tekst bez
    /// tłumaczenia po drodze; to dogeokodowuje je w języku ODBIORCY).
    static func localizedCityName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: appLocale).first?.locality
    }
}
