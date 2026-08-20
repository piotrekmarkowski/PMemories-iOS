import Foundation
import SwiftData
import CoreLocation

/// Trwały zapis podróży z Travel Map (SwiftData) — pierwszy kawałek warstwy
/// persystencji z `Docs/Database.md` (Etap 1 "Fundament"). Przed tym appka
/// NIE zapisywała żadnej podróży między uruchomieniami — `TripStop` z
/// `TravelMap.swift` żyje tylko w pamięci na czas jednej sesji animacji.
/// Nazwy `SavedTrip`/`SavedStop` (nie `Trip`/`TripStop`) celowo różne od
/// istniejącego, ulotnego `TripStop`, żeby nie mylić dwóch warstw.
@Model
final class SavedTrip {
    // Wartości domyślne przy deklaracji na wszystkich polach — patrz
    // `ProjectPersistence.swift` po pełne uzasadnienie (błąd migracji
    // SwiftData psujący całą bazę, 28.07.2026).
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \SavedStop.trip)
    var stops: [SavedStop] = []

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), stops: [SavedStop] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.stops = stops
    }
}

@Model
final class SavedStop {
    var cityName: String = ""
    var country: String?
    var countryCode: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var transportRawValue: String = TransportMode.plane.rawValue
    /// Kolejność w trasie — SwiftData nie gwarantuje kolejności relacji.
    var order: Int = 0
    /// Kiedy user faktycznie był w tym miejscu — opcjonalne, wpisywane
    /// ręcznie (nie data utworzenia rekordu w appce).
    var arrivalDate: Date?
    /// Dystans TEGO odcinka (od poprzedniego przystanku) w km, liczony przez
    /// `RouteProvider.route` przy zapisie trasy — 0 dla pierwszego przystanku
    /// (brak poprzedniego). Domyślna wartość dla bezpiecznej migracji
    /// SwiftData (istniejące rekordy sprzed tego pola dostają 0, nie crash).
    var legDistanceKm: Double = 0
    /// Statystyki wysokości TEGO odcinka — tylko dla Wędrówki, `nil` dla
    /// pozostałych środków transportu i gdy zapytanie do `ElevationProvider`
    /// się nie powiodło (offline przy zapisie trasy) — nie zgadujemy.
    var elevationGainMeters: Double?
    var highestElevationMeters: Double?
    /// Identyfikator zdjęcia na miniaturce markera tego przystanku — patrz
    /// `TripStop.representativePhotoIdentifier`.
    var representativePhotoIdentifier: String?
    /// `SavedProject.id` ręcznie połączonego filmu — patrz
    /// `TripStop.linkedProjectID` po pełne uzasadnienie.
    var linkedProjectID: UUID?
    var trip: SavedTrip?

    init(
        cityName: String, country: String?, countryCode: String?,
        latitude: Double, longitude: Double, transportRawValue: String, order: Int,
        arrivalDate: Date? = nil, legDistanceKm: Double = 0,
        elevationGainMeters: Double? = nil, highestElevationMeters: Double? = nil,
        representativePhotoIdentifier: String? = nil, linkedProjectID: UUID? = nil
    ) {
        self.cityName = cityName
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.transportRawValue = transportRawValue
        self.order = order
        self.arrivalDate = arrivalDate
        self.legDistanceKm = legDistanceKm
        self.elevationGainMeters = elevationGainMeters
        self.highestElevationMeters = highestElevationMeters
        self.representativePhotoIdentifier = representativePhotoIdentifier
        self.linkedProjectID = linkedProjectID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension SavedTrip {
    /// Odtwarza listę ulotnych `TripStop` (posortowaną) z zapisanej podróży —
    /// do ponownego puszczenia animacji przez `TravelMapAnimationView`.
    var asTripStops: [TripStop] {
        stops.sorted(by: { $0.order < $1.order }).map { saved in
            var stop = TripStop()
            stop.cityName = saved.cityName
            stop.transport = TransportMode(rawValue: saved.transportRawValue) ?? .plane
            stop.coordinate = saved.coordinate
            stop.country = saved.country
            stop.countryCode = saved.countryCode
            stop.arrivalDate = saved.arrivalDate
            stop.representativePhotoIdentifier = saved.representativePhotoIdentifier
            stop.linkedProjectID = saved.linkedProjectID
            return stop
        }
    }

    /// Kody krajów odwiedzonych w tej podróży (bez duplikatów) — do statystyk.
    var countryCodes: Set<String> {
        Set(stops.compactMap(\.countryCode))
    }

    /// Suma dystansów wszystkich odcinków — realny przebyty dystans, nie
    /// linia prosta między pierwszym a ostatnim przystankiem.
    var totalDistanceKm: Double {
        stops.reduce(0) { $0 + $1.legDistanceKm }
    }

    /// Czy ta podróż ma w ogóle odcinek Wędrówki, niezależnie od tego czy
    /// zapytanie o wysokość się powiodło — pozwala UI pokazać "brak danych"
    /// zamiast całkiem ukrywać odznakę wysokości, gdy Wędrówka jest, ale
    /// `ElevationProvider` akurat zawiódł (offline przy zapisie trasy).
    var hasHikingLeg: Bool {
        stops.contains { $0.transportRawValue == TransportMode.hiking.rawValue }
    }

    /// Suma przewyższenia ze WSZYSTKICH odcinków Wędrówki w tej podróży —
    /// `nil` gdy żaden odcinek nie ma danych wysokości (brak Wędrówki albo
    /// zapytanie nie powiodło się przy zapisie), nie pokazujemy "0m" jakby
    /// to była realna, zmierzona wartość.
    var totalElevationGainMeters: Double? {
        let values = stops.compactMap(\.elevationGainMeters)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Najwyższy osiągnięty punkt spośród WSZYSTKICH odcinków Wędrówki.
    var highestElevationMeters: Double? {
        stops.compactMap(\.highestElevationMeters).max()
    }

    /// Liczba dni podróży (od pierwszego do ostatniego `arrivalDate`,
    /// włącznie) — `nil` gdy którykolwiek z tych dwóch dat brakuje (user nie
    /// wypełnił daty, opcjonalne pole), żeby nie zgadywać/zmyślać liczby.
    var dayCount: Int? {
        let sorted = stops.sorted(by: { $0.order < $1.order })
        guard let first = sorted.first?.arrivalDate, let last = sorted.last?.arrivalDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return max(1, days + 1)
    }

    /// Data + statystyki (km/dni/kraje) w jednej linii — km i kraje zawsze
    /// dostępne (liczone z zapisanych przystanków), dni tylko gdy user
    /// wypełnił daty przyjazdu (opcjonalne pole, nie zgadujemy). Przeniesione
    /// z `TravelMapView` (03.08.2026) przy przenosinach listy "Your Trips" do
    /// Badges — ten sam formatowany tekst potrzebny w obu miejscach.
    var subtitle: String {
        var parts = [createdAt.formatted(date: .abbreviated, time: .omitted)]
        if totalDistanceKm > 0 {
            parts.append("\(Int(totalDistanceKm.rounded()).formatted()) km")
        }
        if let dayCount {
            parts.append(dayCount == 1 ? L("1 day") : "\(dayCount) \(L("days"))")
        }
        let countryCount = countryCodes.count
        if countryCount > 1 {
            // Ten sam bug co "7 Kraje"/"13 loty" na Home (11.08.2026) —
            // `L("countries")` zawsze pokazywał tę samą formę, poprawną
            // tylko dla 2-4. `countryCount > 1` wyżej gwarantuje że tu
            // zawsze jest 2+, ale wciąż potrzebuje poprawnej formy dla 5+.
            let label = isPolishLanguageActive
                ? polishPlural(countryCount, one: "kraj", few: "kraje", many: "krajów")
                : L("countries")
            parts.append("\(countryCount) \(label)")
        }
        if hasHikingLeg {
            if let gain = totalElevationGainMeters {
                parts.append("⛰️ \(Int(gain.rounded()).formatted())m")
            } else {
                parts.append("⛰️ \(L("no data"))")
            }
        }
        return parts.joined(separator: " • ")
    }
}
