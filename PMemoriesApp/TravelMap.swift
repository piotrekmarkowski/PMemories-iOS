import CoreLocation
import SwiftUI

/// Środek transportu między dwoma przystankami — wpływa na ikonę animowaną
/// wzdłuż trasy.
enum TransportMode: String, CaseIterable, Identifiable {
    case plane, train, car, boat, cruise, hiking

    var id: String { rawValue }

    /// Emoji do szybkiego skanowania wzrokiem w pickerze (user: "wybór w 2
    /// sekundy, nie przewijanie 15 opcji") — 6 trybów, jeden glif na tryb.
    /// `hiking` używa emoji jako ikony na mapie/w eksporcie (nie tylko w
    /// pickerze) — user: tymczasowe rozwiązanie zanim powstanie własna
    /// pseudo-3D grafika jak dla reszty (29.07.2026).
    var emoji: String {
        switch self {
        case .plane: return "✈️"
        case .train: return "🚆"
        case .car: return "🚗"
        case .boat: return "⛴️"
        case .cruise: return "🛳️"
        case .hiking: return "🥾"
        }
    }

    /// Własna, narysowana grafika (gradient + cień, "pseudo-3D") używana jako
    /// animowany znacznik na mapie — zawsze zwrócona dziobem/przodem "do góry"
    /// (y=0 w naszym rysowniku), więc nie potrzeba żadnej korekty kąta obrotu
    /// jak przy płaskich SF Symbols (np. airplane domyślnie wskazywał NE, nie
    /// N, co dawało wrażenie "lotu bokiem").
    var imageAssetName: String {
        "Vehicle-\(rawValue)"
    }

    var label: String {
        switch self {
        case .plane: return L("Plane")
        case .train: return L("Train")
        case .car: return L("Car")
        case .boat: return L("Ferry")
        case .cruise: return L("Cruise Ship")
        case .hiking: return L("Hiking")
        }
    }
}

/// Jeden przystanek podróży. `transport` opisuje, jak dotarto DO tego
/// przystanku (ignorowane dla pierwszego, bo nie ma poprzedniego odcinka).
struct TripStop: Identifiable {
    let id = UUID()
    var cityName: String = ""
    var transport: TransportMode = .plane
    var coordinate: CLLocationCoordinate2D?
    var country: String?
    var countryCode: String?
    /// Region administracyjny pierwszego poziomu (04.09.2026) — potrzebny
    /// WYŁĄCZNIE dla Wielkiej Brytanii: Apple nie ma osobnych kodów ISO dla
    /// Anglii/Szkocji/Walii/Irlandii Płn. (wszystko to "GB"), ale user chce
    /// osobne pieczątki paszportowe dla każdej z tych 4 — patrz
    /// `TravelAchievementsCalculator.passportCountries` gdzie to się
    /// faktycznie wykorzystuje. Dla reszty świata pole nieużywane.
    var administrativeArea: String?
    /// Kiedy user faktycznie był w tym miejscu — opcjonalne (nie chcemy
    /// wymuszać dodatkowego kroku w szybkim wpisywaniu trasy). Potrzebne na
    /// przyszłość dla "X dni", Travel Time Machine, Travel Wrapped.
    var arrivalDate: Date?
    /// Identyfikator zdjęcia reprezentującego ten przystanek na markerze
    /// mapy (miniaturka zamiast zwykłej kropki) — wypełniane automatycznie
    /// przez Smart Route (pierwsze chronologicznie zdjęcie z klastra) albo
    /// ręcznie w `StopRow`.
    var representativePhotoIdentifier: String?
    /// `SavedProject.id` filmu który powstał z tej podróży/miejsca — ustawiane
    /// WYŁĄCZNIE ręcznie (przycisk "Połącz z filmem" w `StopRow`), nigdy
    /// zgadywane. Napędza World Globe: tap na miejsce → Library z tym
    /// projektem podświetlonym.
    var linkedProjectID: UUID?

    var isResolved: Bool { coordinate != nil }
}

enum CityGeocoder {
    static func resolve(_ stop: TripStop) async -> TripStop {
        var resolved = stop
        guard !stop.cityName.trimmingCharacters(in: .whitespaces).isEmpty else { return resolved }

        let geocoder = CLGeocoder()
        let placemark = try? await AsyncTimeout.run(seconds: 10) {
            try await geocoder.geocodeAddressString(stop.cityName).first
        }
        guard let placemark = placemark ?? nil, let location = placemark.location else {
            return resolved
        }

        resolved.coordinate = location.coordinate
        resolved.country = placemark.country
        resolved.countryCode = placemark.isoCountryCode
        resolved.administrativeArea = placemark.administrativeArea
        return resolved
    }

    /// Odwrotne geokodowanie — nazwa miasta z surowej lokalizacji GPS.
    /// Używane do automatycznego nazywania projektu miejscem zamiast samej
    /// daty (user: "cel podróży" zamiast generycznego "Memory <data>").
    static func reverseResolve(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return placeName(from: placemark)
    }

    /// Jak `reverseResolve`, ale zachowuje też kraj/kod kraju (potrzebne dla
    /// `SavedStop.country`/`countryCode` w Smart Route) — `reverseResolve`
    /// je dziś liczy wewnętrznie, ale odrzuca, zwracając samą nazwę miasta.
    static func reverseResolveFull(_ location: CLLocation) async -> (city: String, country: String?, countryCode: String?)? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
              let city = placeName(from: placemark) else {
            return nil
        }
        return (city, placemark.country, placemark.isoCountryCode)
    }

    /// 12.09.2026, zgłoszony bug (user: zdjęcie z plaży Elafonisi na Krecie
    /// dostało podpis "Grecja, Greece" zamiast nazwy plaży) — przyczyna:
    /// odległe, niezaludnione miejsca (plaże, szczyty) często nie mają
    /// `locality`/`administrativeArea` w odpowiedzi Apple'owego geokodera,
    /// więc łańcuch spadał od razu do samej nazwy kraju. Dodane pośrednie
    /// szczeble ŁAŃCUCHA PRZED krajem: `subLocality` (dzielnica/okolica),
    /// `areasOfInterest` (nazwane punkty zainteresowania — DOKŁADNIE tu
    /// Apple trzyma nazwy typu "Elafonissi Beach" dla znanych miejsc bez
    /// własnej miejscowości), `name` (surowy adres/POI jako ostatnia deska
    /// przed regionem/krajem).
    private static func placeName(from placemark: CLPlacemark) -> String? {
        placemark.locality
            ?? placemark.subLocality
            ?? placemark.areasOfInterest?.first
            ?? placemark.name
            ?? placemark.administrativeArea
            ?? placemark.country
    }

    /// Skraca nazwę lotniska — user 30.07.2026: "London (STN) → Lanzarote
    /// (ACE)". Najpierw próbuje dopasować WSPÓŁRZĘDNE do `AirportDatabase`
    /// (realne kody IATA, nie zgadywanie) — dopiero gdy nic nie pasuje
    /// (małe/regionalne lotnisko spoza listy), wraca do bezpiecznego
    /// obcięcia słowa "Airport" (np. "César Manrique–Lanzarote Airport" →
    /// "César Manrique–Lanzarote") — świadomie NIE próbuje zgadywać która
    /// połowa nazwy to miasto, wzorzec nazw jest zbyt niespójny.
    static func shortenedAirportName(_ name: String, coordinate: CLLocationCoordinate2D? = nil) -> String {
        let suffix = " Airport"
        guard name.hasSuffix(suffix) else { return name }
        if let coordinate, let airport = AirportDatabase.nearest(to: coordinate) {
            return "\(airport.city) (\(airport.iata))"
        }
        return String(name.dropLast(suffix.count))
    }

    static func flagEmoji(countryCode: String?) -> String {
        guard let countryCode, countryCode.count == 2 else { return "🌍" }
        return countryCode.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = UnicodeScalar(127397 + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }
}
