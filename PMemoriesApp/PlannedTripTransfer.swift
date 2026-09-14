import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Wysyłanie zaplanowanej podróży do kogoś innego (np. towarzysza lotu,
/// żeby nie musiał wpisywać wszystkiego od nowa) — user 11.08.2026: "musimy
/// mieć możliwość wysłania do kogoś zaplanowanej wycieczki żeby nie trzeba
/// było wpisywać jak ktoś ma stworzone i leci z tobą". Świadomie prosty
/// plik przez natywny Share Sheet (AirDrop/Messages/Mail), NIE `CKShare`
/// (live współdzielenie z zarządzaniem uczestnikami) — user chce jednorazową
/// kopię, nie stały link do tej samej podróży.
extension UTType {
    static var pmemoriesTrip: UTType {
        UTType(exportedAs: "com.piotrmarkowski.pmemories.trip", conformingTo: .json)
    }
}

private extension JSONEncoder {
    static var pmemoriesTrip: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pmemoriesTrip: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Backend linku do podróży (12.08.2026, user: "share ma przejść i się
/// zapisywać w appce od razu w zaplanowanych, jak się otworzy link") —
/// plik `.pmtrip` (poniżej) nie działa przez appki które NIE przyjmują
/// niestandardowych plików w swoim rozszerzeniu udostępniania (Messenger i
/// większość komunikatorów, sprawdzone: przyjmują tylko obraz/film/URL/
/// tekst). Link ZAWSZE działa — otwiera appkę przez Universal Link
/// (Associated Domains, `apple-app-site-association`) i pobiera dane z
/// małego serwisu na VPS (`pmemories_share_server.py`, ten sam wzorzec co
/// istniejący backend zapisów MacAmp — czysty Python, bez zależności).
/// Domena `pmemories.duckdns.org` (13.08.2026) — osobna, dedykowana
/// PMemories zamiast osobistej domeny portfolio; stara domena zostaje w
/// `com.apple.developer.associated-domains` i po stronie nginx, żeby
/// wcześniej wysłane linki nie przestały działać.
enum ShareLinkService {
    private static let baseURL = URL(string: "https://pmemories.duckdns.org/pmemories")!

    enum ServiceError: Error {
        case invalidResponse
    }

    /// Budowa linku z JUŻ znanego ID, bez wywołania sieciowego — reużywane
    /// gdy podróż ma już `shareID` (16.08.2026), zamiast tworzyć drugi
    /// równoległy rekord na serwerze przy każdym tapnięciu Share.
    static func tripURL(id: String) -> URL {
        baseURL.appendingPathComponent("trip/\(id)")
    }

    static func createShareLink(for dto: TripTransferDTO) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/trips"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.pmemoriesTrip.encode(dto)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }
        struct CreateResponse: Decodable { let id: String }
        let decoded = try JSONDecoder().decode(CreateResponse.self, from: data)
        return baseURL.appendingPathComponent("trip/\(decoded.id)")
    }

    /// `url.lastPathComponent` (ID podróży) — wołane z `.onOpenURL` gdy
    /// user otworzy link `https://piotrmarkowski.duckdns.org/pmemories/trip/<id>`,
    /// czy to przez Universal Link, czy ręcznie w przeglądarce z otwartą appką.
    /// Też reużywane do PULL odświeżenia współdzielonej podróży (16.08.2026,
    /// patrz `PlannedTrip.shareID`) — ten sam GET, inny wywołujący.
    static func fetchTrip(id: String) async throws -> TripTransferDTO {
        let url = baseURL.appendingPathComponent("api/trips/\(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }
        return try JSONDecoder.pmemoriesTrip.decode(TripTransferDTO.self, from: data)
    }

    /// PUSH aktualizacji do JUŻ istniejącego rekordu (16.08.2026, user:
    /// "mamy server ktory moze dzialac do wymiany tych danych wiec dzialamy"
    /// — po zgłoszeniu że zmiany narzeczonej nie docierały do usera, bo
    /// dotychczasowe udostępnianie to była jednorazowa kopia, nie żywe
    /// połączenie). Serwer nadpisuje TYLKO gdy `id` już istnieje (404
    /// inaczej — nie tworzy nowych rekordów pod nieznanym ID, patrz
    /// `pmemories_share_server.py do_PUT`). "Ostatni zapis wygrywa", bez
    /// scalania konfliktów — wystarczające dla 2-3 osób planujących razem.
    static func updateSharedTrip(id: String, dto: TripTransferDTO) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/trips/\(id)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.pmemoriesTrip.encode(dto)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }
    }
}

struct PlaceTransferDTO: Codable {
    var name: String
    var statusRawValue: String
    var order: Int
    var dayIndex: Int?
}

struct StopTransferDTO: Codable {
    var cityName: String
    var country: String?
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    var transportRawValue: String
    var order: Int
    var checkInDate: Date?
    var checkOutDate: Date?
    var transportDepartureTime: Date?
    var transportArrivalTime: Date?
    /// Koszt biletu na tę trasę (18.08.2026) — patrz `PlannedStop.
    /// transportCostAmount`. `nil` domyślnie tylko dla WSTECZNEJ
    /// kompatybilności z linkami wysłanymi przed tą zmianą — nie ma
    /// osobnego `decode` fallbacku, bo `Codable` z `Optional` już
    /// akceptuje brakujący klucz w starszym JSON-ie.
    var transportCostAmount: Double?
    var accommodationRawValue: String?
    var accommodationName: String?
    var accommodationAddress: String?
    var accommodationCostAmount: Double?
    var notes: String
    var placesToVisit: [PlaceTransferDTO]
}

/// Ładunek pliku `.pmtrip` — `Transferable`, żeby `ShareLink` mógł go od
/// razu zaoferować bez ręcznego zarządzania plikiem tymczasowym.
struct TripTransferDTO: Codable, Transferable {
    var title: String
    var tripDescription: String
    var startDate: Date?
    var endDate: Date?
    var stops: [StopTransferDTO]
    var currencyCode: String
    var flightCostAmount: Double?
    var estimatedCostAmount: Double?
    var isWholePackage: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pmemoriesTrip) { dto in
            try JSONEncoder.pmemoriesTrip.encode(dto)
        }
        .suggestedFileName { dto in
            let name = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name.isEmpty ? "Trip" : name).pmtrip"
        }
        // BEZ `ProxyRepresentation` tutaj (12.08.2026) — jedyny sposób na
        // link wymaga wywołania sieciowego (POST do `ShareLinkService`),
        // a `ProxyRepresentation`'s wariant asynchroniczny jest oznaczony
        // przez Apple jako `deprecated` od iOS 17 ("a synchronous exporter
        // should be used instead") — sprawdzone bezpośrednio w kompilatorze
        // (warning), potwierdzone też w dokumentacji `CoreTransferable`.
        // Link generowany osobno, PRZED pokazaniem `ShareLink`, patrz
        // `PlannedTripDetailView.toolbarContent` w `TripPlanningView.swift`.
    }
}

extension PlannedTrip {
    var transferDTO: TripTransferDTO {
        TripTransferDTO(
            title: title, tripDescription: tripDescription, startDate: startDate, endDate: endDate,
            stops: (stops ?? []).sorted(by: { $0.order < $1.order }).map { stop in
                StopTransferDTO(
                    cityName: stop.cityName, country: stop.country, countryCode: stop.countryCode,
                    latitude: stop.latitude, longitude: stop.longitude,
                    transportRawValue: stop.transportRawValue, order: stop.order,
                    checkInDate: stop.checkInDate, checkOutDate: stop.checkOutDate,
                    transportDepartureTime: stop.transportDepartureTime, transportArrivalTime: stop.transportArrivalTime,
                    transportCostAmount: stop.transportCostAmount,
                    accommodationRawValue: stop.accommodationRawValue,
                    accommodationName: stop.accommodationName, accommodationAddress: stop.accommodationAddress,
                    accommodationCostAmount: stop.accommodationCostAmount,
                    notes: stop.notes,
                    placesToVisit: (stop.placesToVisit ?? []).sorted(by: { $0.order < $1.order }).map {
                        PlaceTransferDTO(name: $0.name, statusRawValue: $0.statusRawValue, order: $0.order, dayIndex: $0.dayIndex)
                    }
                )
            },
            currencyCode: currencyCode, flightCostAmount: flightCostAmount,
            estimatedCostAmount: estimatedCostAmount, isWholePackage: isWholePackage
        )
    }
}

extension PlannedTrip {
    /// "Podziel się jako szablon" (26.08.2026, user po zobaczeniu pierwszej
    /// wersji na `SavedTrip`: "to nie to, o to mi chodziło" wskazując na
    /// EKRAN Planned Trips) — inspiracja dla kogoś, kto NIE leci z nami
    /// (w odróżnieniu od `transferDTO` wyżej, żywe współplanowanie TEJ
    /// SAMEJ podróży z towarzyszem lotu). Reużywa ten sam `TripTransferDTO`/
    /// plik `.pmtrip`/import w `HomeView.importTrip`. `placesToVisit`
    /// ZOSTAJE (atrakcje są częścią "trasy", nie daty), ale `statusRawValue`/
    /// `dayIndex` resetowane — odbiorca jeszcze nie ma dni ustalonych.
    var templateTransferDTO: TripTransferDTO {
        TripTransferDTO(
            title: title, tripDescription: "", startDate: nil, endDate: nil,
            stops: (stops ?? []).sorted(by: { $0.order < $1.order }).map { stop in
                StopTransferDTO(
                    cityName: stop.cityName, country: stop.country, countryCode: stop.countryCode,
                    latitude: stop.latitude, longitude: stop.longitude,
                    transportRawValue: stop.transportRawValue, order: stop.order,
                    checkInDate: nil, checkOutDate: nil,
                    transportDepartureTime: nil, transportArrivalTime: nil,
                    transportCostAmount: nil,
                    accommodationRawValue: nil, accommodationName: nil, accommodationAddress: nil,
                    accommodationCostAmount: nil,
                    notes: "",
                    placesToVisit: (stop.placesToVisit ?? []).sorted(by: { $0.order < $1.order }).map {
                        PlaceTransferDTO(name: $0.name, statusRawValue: PlaceVisitStatus.wantToVisit.rawValue, order: $0.order, dayIndex: nil)
                    }
                )
            },
            currencyCode: Locale.current.currency?.identifier ?? "USD",
            flightCostAmount: nil, estimatedCostAmount: nil, isWholePackage: false
        )
    }
}

extension SavedTrip {
    /// "Podziel się jako szablon" (26.08.2026, user: stara/odbyta podróż
    /// jako inspiracja dla kogoś innego — INNY przypadek niż
    /// `PlannedTrip.transferDTO` wyżej, tam obie strony faktycznie razem
    /// planują TĘ SAMĄ podróż). Reużywa DOKŁADNIE ten sam `TripTransferDTO`/
    /// plik `.pmtrip`/import w `HomeView.importTrip` — odbiorca i tak zawsze
    /// ląduje z NOWĄ, niezależną `PlannedTrip` z tej samej ścieżki kodu,
    /// zero nowego typu pliku. Świadomie BEZ dat/kosztów/noclegu (user:
    /// "date itp każdy sobie ustala na nowo, zostają miejsca") — `SavedStop`
    /// i tak nie ma pól noclegu/kosztu, ale `arrivalDate` trzeba jawnie
    /// pominąć, żeby odbiorca nie dostał dat NASZEJ wycieczki jako swoich.
    var templateTransferDTO: TripTransferDTO {
        TripTransferDTO(
            title: title, tripDescription: "", startDate: nil, endDate: nil,
            stops: stops.sorted(by: { $0.order < $1.order }).map { stop in
                StopTransferDTO(
                    cityName: stop.cityName, country: stop.country, countryCode: stop.countryCode,
                    latitude: stop.latitude, longitude: stop.longitude,
                    transportRawValue: stop.transportRawValue, order: stop.order,
                    checkInDate: nil, checkOutDate: nil,
                    transportDepartureTime: nil, transportArrivalTime: nil,
                    transportCostAmount: nil,
                    accommodationRawValue: nil, accommodationName: nil, accommodationAddress: nil,
                    accommodationCostAmount: nil,
                    notes: "", placesToVisit: []
                )
            },
            currencyCode: Locale.current.currency?.identifier ?? "USD",
            flightCostAmount: nil, estimatedCostAmount: nil, isWholePackage: false
        )
    }
}

extension TripTransferDTO {
    /// Współdzielona budowa `[PlannedStop]` z DTO — użyta zarówno przy
    /// pierwszym imporcie (`makePlannedTrip`) jak i przy nadpisywaniu
    /// ISTNIEJĄCEJ podróży świeżą wersją z serwera (`PlannedTrip.
    /// applyRemoteUpdate`, 16.08.2026). Zawsze ŚWIEŻE obiekty `@Model` —
    /// wołający decyduje co zrobić ze starymi (insert dla nowej podróży,
    /// delete dla nadpisania).
    fileprivate func makePlannedStops() -> [PlannedStop] {
        stops.map { s in
            PlannedStop(
                cityName: s.cityName, country: s.country, countryCode: s.countryCode,
                latitude: s.latitude, longitude: s.longitude,
                transportRawValue: s.transportRawValue, order: s.order,
                checkInDate: s.checkInDate, checkOutDate: s.checkOutDate,
                transportDepartureTime: s.transportDepartureTime, transportArrivalTime: s.transportArrivalTime,
                transportCostAmount: s.transportCostAmount,
                accommodationRawValue: s.accommodationRawValue,
                accommodationName: s.accommodationName, accommodationAddress: s.accommodationAddress,
                accommodationCostAmount: s.accommodationCostAmount,
                notes: s.notes,
                placesToVisit: s.placesToVisit.map {
                    PlaceToVisit(name: $0.name, statusRawValue: $0.statusRawValue, order: $0.order, dayIndex: $0.dayIndex)
                }
            )
        }
    }

    /// Nowe obiekty `@Model` bez `id`/relacji ze źródła — odbiorca dostaje
    /// WŁASNĄ, niezależną kopię, nie żywe powiązanie z podróżą nadawcy.
    func makePlannedTrip() -> PlannedTrip {
        let plannedStops = makePlannedStops()
        return PlannedTrip(
            title: title, tripDescription: tripDescription, startDate: startDate, endDate: endDate, stops: plannedStops,
            currencyCode: currencyCode, flightCostAmount: flightCostAmount,
            estimatedCostAmount: estimatedCostAmount, isWholePackage: isWholePackage
        )
    }

    static func decode(from data: Data) throws -> TripTransferDTO {
        try JSONDecoder.pmemoriesTrip.decode(TripTransferDTO.self, from: data)
    }
}

extension PlannedTrip {
    /// Nadpisuje TĘ SAMĄ, już zapisaną podróż świeżą wersją z serwera
    /// (16.08.2026, PULL odświeżenia współdzielonej podróży) — w
    /// odróżnieniu od `makePlannedTrip()` (nowa, niezależna kopia) to
    /// aktualizuje istniejący obiekt `@Model` na miejscu, żeby `@Query`/
    /// `@Bindable` widoki (np. `PlannedTripDetailView`) same się przemalowały.
    /// Stare przystanki są USUWANE (kaskada kasuje ich `PlaceToVisit`) i
    /// zastępowane świeżymi z DTO — "ostatni zapis wygrywa", zero scalania
    /// pole-po-polu.
    func applyRemoteUpdate(_ dto: TripTransferDTO, modelContext: ModelContext) {
        title = dto.title
        tripDescription = dto.tripDescription
        startDate = dto.startDate
        endDate = dto.endDate
        currencyCode = dto.currencyCode
        flightCostAmount = dto.flightCostAmount
        estimatedCostAmount = dto.estimatedCostAmount
        isWholePackage = dto.isWholePackage

        // Status "odwiedzone"/"chcę odwiedzić" per miejsce ZAPAMIĘTANY przed
        // skasowaniem starych przystanków (05.09.2026, user: "jeśli naznaczę
        // coś co odwiedziłem... nic nie zostaje zapisane") — DTO ze
        // współdzielonego serwera to zawsze pierwotny SZABLON, nigdy nie ma w
        // sobie lokalnego postępu drugiej osoby, więc "ostatni zapis wygrywa"
        // bez tego kroku po cichu resetował wszystkie odhaczone checkboxy przy
        // każdym odświeżeniu. Klucz: miasto+nazwa miejsca+dzień (case-
        // insensitive) — wystarczająco unikalne w obrębie jednej podróży.
        var statusByKey: [String: String] = [:]
        for stop in stops ?? [] {
            for place in stop.placesToVisit ?? [] {
                let key = Self.placeStatusKey(city: stop.cityName, placeName: place.name, dayIndex: place.dayIndex)
                statusByKey[key] = place.statusRawValue
            }
        }

        for stop in stops ?? [] {
            modelContext.delete(stop)
        }
        let newStops = dto.makePlannedStops()
        for stop in newStops {
            for place in stop.placesToVisit ?? [] {
                let key = Self.placeStatusKey(city: stop.cityName, placeName: place.name, dayIndex: place.dayIndex)
                if let preservedStatus = statusByKey[key] {
                    place.statusRawValue = preservedStatus
                }
            }
            modelContext.insert(stop)
        }
        stops = newStops
    }

    private static func placeStatusKey(city: String, placeName: String, dayIndex: Int?) -> String {
        "\(city.trimmingCharacters(in: .whitespaces).lowercased())|||\(placeName.trimmingCharacters(in: .whitespaces).lowercased())|||\(dayIndex.map(String.init) ?? "any")"
    }
}
