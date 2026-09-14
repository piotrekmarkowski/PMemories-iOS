import Foundation
import SwiftData
import CoreLocation

/// Trwały zapis PLANOWANEJ (jeszcze nieodbytej) podróży — "Trip Planning /
/// My Next Journey" (`Docs/TODO.md`, P1 z analizy konkurencji 10.08.2026).
/// Świadomie OSOBNY model od `SavedTrip`/`SavedStop` (`TripPersistence.swift`)
/// — tamte zakładają że podróż już się odbyła (dystans/wysokość liczone
/// przez `RouteProvider`/`ElevationProvider` PRZY ZAPISIE trasy,
/// `arrivalDate` = "kiedy user faktycznie był"). Tu nic z tego jeszcze nie
/// istnieje.
///
/// **Model zrewidowany 11.08.2026** (przed tym nikt jeszcze nie miał
/// zapisanych prawdziwych planów — bezpieczny moment na zmianę) na
/// podstawie przemyślanego feedbacku usera: Accommodation jako JEDEN
/// uniwersalny element (Hotel/Airbnb/.../"At home"), pary dat pobytu
/// zamiast jednej daty, Places to visit per przystanek. Świadomie NADAL
/// BEZ Budget/Reservations/day-by-day itinerary/"travelling with" — to by
/// kopiowało TripMapper 1:1, PMemories nie musi tego wygrywać (`TODO.md`).
@Model
final class PlannedTrip {
    // Wartości domyślne przy deklaracji na wszystkich polach — ten sam
    // wzorzec co `SavedTrip`/`SavedProject` (lightweight migration SwiftData,
    // patrz `ProjectPersistence.swift` po pełne uzasadnienie).
    var id: UUID = UUID()
    var title: String = ""
    /// NIE `description` — kolizja z `NSObject.description` (`@Model`
    /// mostkuje do Core Data/NSObject), realne ryzyko crasha/dziwnych bugów.
    var tripDescription: String = ""
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date = Date()
    /// Budżet (12.08.2026, user: "można dodać koszty podróży i noclegu,
    /// wtedy jeśli ktoś będzie chciał, to może komuś polecić" — szacowany
    /// koszt jako powód by polecić własną trasę znajomemu, nie pełny
    /// tracker wydatków jak TripMapper). JEDNA waluta na całą podróż
    /// (świadome uproszczenie — appka nie przelicza kursów). Domyślnie
    /// waluta usera z ustawień regionalnych telefonu.
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    /// Koszt lotów — WYDZIELONY z ogólnego pola (12.08.2026, user: "koszty
    /// przelotów musimy dodać na górze, żeby się sumował" — loty zwykle
    /// największy, najbardziej "polecalny" koszt trasy, zasługuje na
    /// własną linijkę zamiast ginąć w ogólnym worku). `nil` = nie wypełnione.
    var flightCostAmount: Double?
    /// Transport/atrakcje/inne — LUB, gdy `wholePackage == true`, CAŁA
    /// kwota wycieczki all-inclusive z biura podróży (user: "chyba że to
    /// wycieczka all in z biura podróży, wtedy możemy wpisać całą kwotę
    /// tam"). Nocleg ma własne pole per przystanek
    /// (`PlannedStop.accommodationCostAmount`), pomijane w sumie gdy
    /// `wholePackage == true` (już wliczone w tę jedną kwotę).
    var estimatedCostAmount: Double?
    /// Gdy `true`, `estimatedCostAmount` to CAŁY koszt wycieczki (pakiet od
    /// biura podróży) — `totalEstimatedCost` wtedy NIE dodaje osobno lotów
    /// ani noclegu, żeby nie zdublować tej samej kwoty.
    var isWholePackage: Bool = false
    // `[PlannedStop]?`, NIE zwykła tablica (12.08.2026, Shared Trip/CKShare)
    // — realny crash na starcie, złapany w konsoli, nie zgadywany: "CloudKit
    // integration requires that all relationships be optional" obejmuje
    // TEŻ relacje to-many (tablice), nie tylko pojedyncze jak przy pierwszym
    // takim buggu 02.08.2026. Wszystkie miejsca czytające `.stops`
    // przełączone na `?? []`.
    @Relationship(deleteRule: .cascade, inverse: \PlannedStop.trip)
    var stops: [PlannedStop]? = []

    /// ID rekordu na serwerze (16.08.2026, żywa synchronizacja przez
    /// `pmemories_share_server.py`) — `nil` = nigdy nie udostępniona (albo
    /// zaimportowana z pliku `.pmtrip`, offline, bez serwera). Gdy ustawione,
    /// TA SAMA wartość jest po obu stronach (nadawca po pierwszym share,
    /// odbiorca po zaimportowaniu linku) — obie strony mogą PUSHować edycje
    /// (PUT) i PULLować odświeżenie (GET) pod tym samym ID, "ostatni zapis
    /// wygrywa". Patrz `TripPlanningView.PlannedTripDetailView`.
    var shareID: String?

    /// Karta "Welcome back" na Home trwale wyciszona dla TEJ podróży
    /// (09.09.2026, user: dostał kartę-przypomnienie o Rumunii, nie chciał
    /// jeszcze tworzyć filmu, ale to blokowało pokazanie kolejnej,
    /// nadchodzącej podróży za 9 dni — `featuredPlannedTrip` ma tylko JEDNO
    /// miejsce na Home, `justCompleted` miało pierwszeństwo bezwarunkowo).
    /// Ten sam duch co `SavedStop.isHiddenFromOnThisDay` — chowa TYLKO
    /// przypomnienie, sama podróż zostaje w pełni widoczna/edytowalna w
    /// Trip Planning (i wciąż można stamtąd ręcznie stworzyć film).
    var isMemoryPromptDismissed: Bool = false

    init(
        id: UUID = UUID(), title: String, tripDescription: String = "",
        startDate: Date? = nil, endDate: Date? = nil, createdAt: Date = Date(), stops: [PlannedStop] = [],
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        flightCostAmount: Double? = nil, estimatedCostAmount: Double? = nil, isWholePackage: Bool = false,
        shareID: String? = nil, isMemoryPromptDismissed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tripDescription = tripDescription
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.stops = stops
        self.currencyCode = currencyCode
        self.flightCostAmount = flightCostAmount
        self.estimatedCostAmount = estimatedCostAmount
        self.isWholePackage = isWholePackage
        self.shareID = shareID
        self.isMemoryPromptDismissed = isMemoryPromptDismissed
    }
}

@Model
final class PlannedStop {
    var cityName: String = ""
    var country: String?
    var countryCode: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var transportRawValue: String = TransportMode.plane.rawValue
    /// Kolejność w planie — SwiftData nie gwarantuje kolejności relacji.
    var order: Int = 0
    /// Pobyt W TYM miejscu — para dat zamiast jednej (11.08.2026, user:
    /// "16 Apr → 23 Apr" per miejsce, appka sama liczy noce). Od 12.08.2026
    /// zawierają też godzinę (`DatePicker` z `.hourAndMinute`, user: "skoro
    /// planujemy podróż, musi być o jakimś czasie") — wcześniej sam dzień.
    var checkInDate: Date?
    var checkOutDate: Date?
    /// Godzina odjazdu/przyjazdu środka transportu DO tego przystanku
    /// (12.08.2026, user: "jak ktoś bierze cruise, nie ma czasu... musi
    /// być o jakimś czasie") — osobne od `checkInDate`/`checkOutDate`
    /// (te opisują pobyt w noclegu, nie sam transport). Tylko GODZINA
    /// (`.hourAndMinute`), nie pełna data — appka już zna DZIEŃ z reszty
    /// planu, user wpisuje tylko porę.
    var transportDepartureTime: Date?
    var transportArrivalTime: Date?
    /// Koszt biletu/transportu NA TĘ konkretną trasę (18.08.2026, user
    /// pokazał realną notatkę z planowania Tajlandii: bilety wewnętrzne
    /// Bangkok→Chiang Mai/Chiang Mai→Phuket jako OSOBNE koszty per-etap,
    /// nie jeden zbiorczy `PlannedTrip.flightCostAmount` na całą podróż).
    /// Ten sam wzorzec co `accommodationCostAmount` niżej — w walucie
    /// całej podróży, `nil` = nie wypełnione. Edytowane z wiersza
    /// PRZYSTANKU ŹRÓDŁOWEGO (razem z Departure time, ten sam `nextStop`
    /// binding co czas — patrz `TripPlanningView.PlannedStopRow`), choć
    /// fizycznie żyje przy przystanku DOCELOWYM (spójne z
    /// `transportDepartureTime`/`transportArrivalTime` wyżej).
    var transportCostAmount: Double?
    /// `nil` = user pominął ten krok (np. appka nie wymusza wyboru typu
    /// noclegu). Surowy `AccommodationType.rawValue`.
    var accommodationRawValue: String?
    /// Konkretna nazwa noclegu (11.08.2026, user: "Hilton London" — dla
    /// `.other` służy też jako opis własnego typu, jak dotąd). Zawsze
    /// OPCJONALNA dla WSZYSTKICH typów, nie tylko `.other` — user: "adres
    /// i nazwa powinny być opcjonalne".
    var accommodationName: String?
    /// Opcjonalny adres noclegu — jak wyżej, nigdy wymagany.
    var accommodationAddress: String?
    /// Szacowany koszt TEGO noclegu (12.08.2026, Budget) — w walucie całej
    /// podróży (`PlannedTrip.currencyCode`), `nil` = nie wypełnione.
    var accommodationCostAmount: Double?
    /// Loty/rezerwacje/inne wolne notatki — węższe niż w Etapie 1, bo
    /// nocleg ma już własną strukturę (Accommodation) zamiast być częścią
    /// tego pola.
    var notes: String = ""
    // `[PlaceToVisit]?` — ten sam powód co `PlannedTrip.stops` wyżej.
    @Relationship(deleteRule: .cascade, inverse: \PlaceToVisit.stop)
    var placesToVisit: [PlaceToVisit]? = []
    var trip: PlannedTrip?

    init(
        cityName: String, country: String? = nil, countryCode: String? = nil,
        latitude: Double = 0, longitude: Double = 0,
        transportRawValue: String = TransportMode.plane.rawValue, order: Int = 0,
        checkInDate: Date? = nil, checkOutDate: Date? = nil,
        transportDepartureTime: Date? = nil, transportArrivalTime: Date? = nil,
        transportCostAmount: Double? = nil,
        accommodationRawValue: String? = nil, accommodationName: String? = nil, accommodationAddress: String? = nil,
        accommodationCostAmount: Double? = nil,
        notes: String = "", placesToVisit: [PlaceToVisit] = []
    ) {
        self.cityName = cityName
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.transportRawValue = transportRawValue
        self.order = order
        self.checkInDate = checkInDate
        self.checkOutDate = checkOutDate
        self.transportDepartureTime = transportDepartureTime
        self.transportArrivalTime = transportArrivalTime
        self.transportCostAmount = transportCostAmount
        self.accommodationRawValue = accommodationRawValue
        self.accommodationName = accommodationName
        self.accommodationAddress = accommodationAddress
        self.accommodationCostAmount = accommodationCostAmount
        self.notes = notes
        self.placesToVisit = placesToVisit
    }

    var coordinate: CLLocationCoordinate2D? {
        get { latitude == 0 && longitude == 0 ? nil : CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue?.latitude ?? 0
            longitude = newValue?.longitude ?? 0
        }
    }

    /// `nil` gdy brakuje którejkolwiek daty — zero zgadywania, ten sam duch
    /// co reszta appki (np. `SavedTrip.dayCount`).
    var nights: Int? {
        guard let checkInDate, let checkOutDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0
        return max(0, days)
    }
}

/// Miejsce do odwiedzenia w konkretnym przystanku (11.08.2026, user:
/// "Places to visit... Must see / Want to visit / Visited"). Świadomie
/// PROSTE — tylko nazwa + status, bez współrzędnych/kategorii/zdjęć (to by
/// zaczęło kopiować pełnoprawny system POI konkurencji).
@Model
final class PlaceToVisit {
    var id: UUID = UUID()
    var name: String = ""
    var statusRawValue: String = PlaceVisitStatus.wantToVisit.rawValue
    var order: Int = 0
    /// Dzień pobytu w TYM przystanku, np. 1 = pierwszy dzień (12.08.2026,
    /// user: "place to visit rozdzielone na dni, żeby był kwadracik który
    /// będziemy odznaczać podczas podróży co zobaczyliśmy"). `nil` = brak
    /// przypisania ("Any day") — user nie musi rozplanowywać wszystkiego
    /// z góry. Liczba ORDYNALNA (1, 2, 3...), NIE data — appka dolicza
    /// prawdziwą datę do etykiety TYLKO gdy `PlannedStop.checkInDate` jest
    /// znane, ale sam numer dnia działa też bez dat (zero wymuszania).
    var dayIndex: Int?
    var stop: PlannedStop?

    init(name: String, statusRawValue: String = PlaceVisitStatus.wantToVisit.rawValue, order: Int = 0, dayIndex: Int? = nil) {
        self.name = name
        self.statusRawValue = statusRawValue
        self.order = order
        self.dayIndex = dayIndex
    }
}

/// Typ noclegu — JEDEN uniwersalny element zamiast osobnych pól "hotel"/
/// "brak noclegu" (11.08.2026, user: "ja bym zrobił to jako jeden
/// uniwersalny element Accommodation, a dopiero wewnątrz user wybiera
/// typ"). `.home`/`.familyFriends` świadomie NIE wymagają dat pobytu w UI
/// (`PlannedStopRow.stayDatesSection`) — user może po prostu zaznaczyć
/// "At home" i skończyć, bez wymuszania dat które nie mają tam sensu.
enum AccommodationType: String, CaseIterable, Identifiable {
    case hotel, airbnb, vacationRental, hostel, camping, familyFriends, home, other

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .hotel: return "🏨"
        case .airbnb: return "🏠"
        case .vacationRental: return "🏡"
        case .hostel: return "🎒"
        case .camping: return "🏕️"
        case .familyFriends: return "🏠"
        case .home: return "🏡"
        case .other: return "✏️"
        }
    }

    var label: String {
        switch self {
        case .hotel: return L("Hotel")
        case .airbnb: return L("Airbnb")
        case .vacationRental: return L("Vacation rental")
        case .hostel: return L("Hostel")
        case .camping: return L("Camping")
        case .familyFriends: return L("Staying with family/friends")
        case .home: return L("My home")
        case .other: return L("Other")
        }
    }
}

/// Status miejsca do odwiedzenia (11.08.2026).
enum PlaceVisitStatus: String, CaseIterable, Identifiable {
    case mustSee, wantToVisit, visited

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .mustSee: return "⭐"
        // Było ❤️ (18.08.2026, user: "po co te serca? to nie aplikacja
        // randkowa") — serce dla "chcę odwiedzić" czytało się jak lajk z
        // appki randkowej, nie jak status na liście podróżniczej. Zakładka
        // pasuje do "zapisane do sprawdzenia", bez romantycznego skojarzenia.
        case .wantToVisit: return "🔖"
        case .visited: return "✓"
        }
    }

    var label: String {
        switch self {
        case .mustSee: return L("Must see")
        case .wantToVisit: return L("Want to visit")
        case .visited: return L("Visited")
        }
    }
}

extension PlannedTrip {
    /// Konwersja do ulotnych `TripStop` dla "Convert Trip → Memory" —
    /// przekazywane do `TravelMapView`, żeby user od razu miał gotowy
    /// szkic trasy do zbudowania zamiast wpisywać wszystko od nowa. Ten sam
    /// wzorzec co `SavedTrip.asTripStops`. `TripStop` obsługuje TYLKO jedną
    /// datę (`arrivalDate`) — `checkInDate` jest najbliższym odpowiednikiem.
    var asTripStops: [TripStop] {
        (stops ?? []).sorted(by: { $0.order < $1.order }).map { planned in
            var stop = TripStop()
            stop.cityName = planned.cityName
            stop.transport = TransportMode(rawValue: planned.transportRawValue) ?? .plane
            stop.coordinate = planned.coordinate
            stop.country = planned.country
            stop.countryCode = planned.countryCode
            stop.arrivalDate = planned.checkInDate
            return stop
        }
    }

    /// "X nights · Y days" — `nil` gdy brakuje którejś daty, nie zgadujemy.
    /// Polska odmiana liczebnikowa (1/2-4/5+) przez `polishPlural` —
    /// user 11.08.2026 sam podał "15 nights" w przykładzie, ta sama pułapka
    /// co "7 Kraje" na Home, więc naprawiona od razu w tym samym miejscu.
    var nightsAndDaysText: String? {
        guard let startDate, let endDate else { return nil }
        let days = (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
        let nights = max(0, days - 1)
        let nightsPart: String
        let daysPart: String
        if isPolishLanguageActive {
            nightsPart = polishPlural(nights, one: "1 noc", few: "\(nights) noce", many: "\(nights) nocy")
            daysPart = polishPlural(days, one: "1 dzień", few: "\(days) dni", many: "\(days) dni")
        } else {
            nightsPart = nights == 1 ? L("1 night") : "\(nights) \(L("nights"))"
            daysPart = days == 1 ? L("1 day") : "\(days) \(L("days"))"
        }
        return "\(nightsPart) · \(daysPart)"
    }

    /// Rzeczywisty zakres dat, np. "16–23 sie" (11.08.2026, user po
    /// zobaczeniu karty z samym czasem trwania: "chyba jeszcze data by się
    /// przydała") — `nightsAndDaysText` mówi TYLE trwa, nie OD KIEDY.
    /// `DateIntervalFormatter` sam dobiera lokalnie poprawny format
    /// (wspólny miesiąc skraca się do "16–23 sie", różne miesiące/lata
    /// pokazuje osobno) zamiast ręcznego składania stringa.
    var dateRangeText: String? {
        guard let startDate, let endDate else { return nil }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: startDate, to: endDate)
    }

    /// Suma budżetu — TRYB "all-inclusive" (`isWholePackage`) liczy TYLKO
    /// `estimatedCostAmount` (już zawiera loty+nocleg+resztę w jednej
    /// kwocie od biura podróży, doliczanie lotów/noclegu osobno by
    /// zdublowało). Tryb zwykły sumuje GŁÓWNY bilet + pozostałe koszty +
    /// nocleg WSZYSTKICH przystanków + koszt transportu KAŻDEGO etapu
    /// (18.08.2026, user pokazał realną notatkę z Tajlandii: bilety
    /// wewnętrzne Bangkok→Chiang Mai/Chiang Mai→Phuket jako osobne kwoty
    /// obok głównego biletu powrotnego — `PlannedStop.transportCostAmount`).
    /// `nil` TYLKO gdy user nie wypełnił ŻADNEGO pola kosztu (zero
    /// zgadywania sumy z niekompletnych danych, ten sam duch co
    /// `looksCompleted`) — gdy wypełnił choć jedno, resztę liczymy jako 0
    /// (user 12.08.2026: budżet ma być szybkim szacunkiem do polecenia
    /// trasy komuś, nie księgowością).
    var totalEstimatedCost: Double? {
        if isWholePackage {
            return estimatedCostAmount
        }
        let stopCosts = (stops ?? []).flatMap { [$0.accommodationCostAmount, $0.transportCostAmount] }
        let amounts = ([flightCostAmount, estimatedCostAmount] + stopCosts).compactMap { $0 }
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +)
    }

    /// Formatowanie w walucie podróży, lokalnie poprawne (symbol przed/po
    /// kwocie, separator tysięcy) przez `NumberFormatter` zamiast ręcznego
    /// składania stringa. Bez groszy — to szacunek, nie rachunek.
    static func formattedCost(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) \(currencyCode)"
    }

    /// Czy podróż wygląda na już ZAKOŃCZONĄ (11.08.2026, user: przycisk
    /// "Convert" powinien zmienić się na "Create Memory from this trip" PO
    /// podróży) — najpóźniejsza znana data (koniec podróży, albo — gdy
    /// user jej nie wypełnił — najpóźniejszy check-out/check-in
    /// przystanku) jest w przeszłości. `false` gdy appka nie zna ŻADNEJ
    /// daty (zero zgadywania — brak dat = domyślnie "jeszcze przed nami").
    var looksCompleted: Bool {
        let stopDates = (stops ?? []).flatMap { [$0.checkOutDate, $0.checkInDate] }.compactMap { $0 }
        guard let latestKnownDate = ([endDate] + stopDates).compactMap({ $0 }).max() else { return false }
        return latestKnownDate < Date()
    }

    // MARK: - Karta "Upcoming Trip" na Home (12.08.2026)
    //
    // User: "zamiast tego co się wyświetla będzie wyświetlała się następna
    // podróż z odliczaniem... jeśli jesteśmy w trakcie, dzień pokazuje co
    // dzisiaj do zobaczenia... jak nie ma nic zaplanowanego, jest to co jest
    // teraz". Ten sam duch co `looksCompleted` wyżej — porównania dni
    // liczone przez `Calendar.startOfDay`, żeby godzina w `checkInDate`
    // (dziś zawiera `.hourAndMinute` od 12.08.2026) nie psuła porównania
    // "czy to DZIŚ".

    /// Start liczony z `startDate`, a gdy user go nie wypełnił — najwcześniejszy
    /// `checkInDate` przystanku (ten sam fallback co `looksCompleted` robi dla
    /// końca). Zero zgadywania gdy appka nie zna ŻADNEJ z tych dat.
    var effectiveStartDate: Date? {
        startDate ?? (stops ?? []).compactMap(\.checkInDate).min()
    }

    var effectiveEndDate: Date? {
        endDate ?? (stops ?? []).compactMap { $0.checkOutDate ?? $0.checkInDate }.max()
    }

    /// Dziś mieści się między startem a końcem (włącznie) — podróż SIĘ
    /// DZIEJE. `false` gdy appka nie zna obu dat (zero zgadywania).
    var isInProgress: Bool {
        guard let start = effectiveStartDate, let end = effectiveEndDate else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.startOfDay(for: start) <= today && today <= calendar.startOfDay(for: end)
    }

    /// Dni do rozpoczęcia — 0 gdy podróż zaczyna się DZIŚ, `nil` gdy start
    /// nieznany albo już minął (już w trakcie/zakończona, patrz `isInProgress`/
    /// `looksCompleted`).
    var daysUntilStart: Int? {
        guard let start = effectiveStartDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: start)
        guard startDay >= today else { return nil }
        return calendar.dateComponents([.day], from: today, to: startDay).day
    }

    /// "Day X of Y" — TYLKO gdy `isInProgress`, X liczone OD 1 (dzień
    /// startu = Day 1, nie Day 0).
    var currentDayNumber: Int? {
        guard isInProgress, let start = effectiveStartDate else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: Date())
        return (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
    }

    var totalDayCount: Int? {
        guard let start = effectiveStartDate, let end = effectiveEndDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return days + 1
    }

    /// Przystanek w którym user "jest dziś", po datach pobytu — `nil` gdy
    /// żaden przystanek nie ma wypełnionych OBU dat pokrywających dzisiaj
    /// (appka wtedy po prostu nie zgaduje która to konkretnie miejscowość).
    var currentStop: PlannedStop? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (stops ?? []).sorted { $0.order < $1.order }.first { stop in
            guard let checkIn = stop.checkInDate else { return false }
            let checkOut = stop.checkOutDate ?? checkIn
            return calendar.startOfDay(for: checkIn) <= today && today <= calendar.startOfDay(for: checkOut)
        }
    }

    /// Miejsca do zobaczenia DZIŚ w `currentStop` — dopasowanie po
    /// `PlaceToVisit.dayIndex` liczonym WZGLĘDEM `checkInDate` TEGO
    /// przystanku (ten sam wzorzec co `StopSummaryCard.dayLabel`). Puste
    /// gdy user nie przypisał dni do miejsc — appka nie zgaduje które.
    var placesToVisitToday: [PlaceToVisit] {
        guard let stop = currentStop, let checkIn = stop.checkInDate else { return [] }
        let calendar = Calendar.current
        let todayIndex = (calendar.dateComponents([.day], from: calendar.startOfDay(for: checkIn), to: calendar.startOfDay(for: Date())).day ?? 0) + 1
        return (stop.placesToVisit ?? [])
            .filter { $0.dayIndex == todayIndex && PlaceVisitStatus(rawValue: $0.statusRawValue) != .visited }
            .sorted { $0.order < $1.order }
    }

    /// Trasa w skrócie, np. "London → Tokyo" — pierwsze i ostatnie miasto z
    /// wypełnioną nazwą, `nil` gdy appka ma za mało danych (0-1 przystanek
    /// z nazwą).
    var routeSummaryText: String? {
        let cities = (stops ?? []).sorted { $0.order < $1.order }.map(\.cityName).filter { !$0.isEmpty }
        guard let first = cities.first, let last = cities.last, first != last else { return cities.first }
        return "\(first) → \(last)"
    }

    /// Godzina odjazdu W DNIU wylotu — transport DO drugiego przystanku
    /// (pierwszy to zwykle miasto startowe, samo w sobie się "nie odjeżdża
    /// do niego"). `nil` gdy user nie wypełnił godziny albo podróż ma tylko
    /// jeden przystanek.
    var departureTimeToday: Date? {
        let sorted = (stops ?? []).sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return nil }
        return sorted[1].transportDepartureTime
    }

    /// Nazwa kraju TYLKO dla podróży jednokrajowej — dla wielokrajowej nie
    /// ma jednej "poprawnej" nazwy do pokazania, appka nie zgaduje którą.
    var singleCountryName: String? {
        let codes = Set((stops ?? []).compactMap(\.countryCode))
        guard codes.count == 1, let code = codes.first,
              let stop = (stops ?? []).first(where: { $0.countryCode == code }) else { return nil }
        return stop.country ?? code
    }

    /// "Brașov → Bucharest" — miasto w którym user JEST DZIŚ (`currentStop`)
    /// i NASTĘPNE po nim w kolejności, gdy oba mają wypełnione nazwy. Samo
    /// miasto obecne, gdy nie ma następnego (ostatni przystanek) albo appka
    /// nie zna trasy dalej. `nil` gdy nie wiadomo nawet gdzie user jest dziś.
    var currentRouteSegmentText: String? {
        guard let current = currentStop else { return nil }
        let sorted = (stops ?? []).sorted { $0.order < $1.order }
        guard let index = sorted.firstIndex(where: { $0.id == current.id }) else {
            return current.cityName.isEmpty ? nil : current.cityName
        }
        if index + 1 < sorted.count, !sorted[index + 1].cityName.isEmpty, !current.cityName.isEmpty {
            return "\(current.cityName) → \(sorted[index + 1].cityName)"
        }
        return current.cityName.isEmpty ? nil : current.cityName
    }

    /// Podróż zakończyła się NIEDAWNO (12.08.2026, karta "Welcome back" na
    /// Home) — okno 7 dni, żeby nie "nagabywać" o Convert w nieskończoność
    /// gdy user faktycznie nie chce jeszcze tego zrobić (może wciąż edytować
    /// zdjęcia gdzie indziej). Po tym oknie karta po prostu znika, Convert
    /// wciąż dostępny ręcznie w Trip Planning.
    ///
    /// 12.09.2026, user: "jesli nie bylo dokladnej daty podrozy to nie
    /// wracal bym ze wspomnieniami" — realny przypadek: bezimienna testowa
    /// podróż (Zakopane → Rysy, dodana przy testowaniu wyszukiwania
    /// szczytu) bez `startDate`/`endDate` na poziomie CAŁEJ podróży, tylko
    /// z przypadkowym `checkInDate` na JEDNYM przystanku — a mimo to
    /// wywołała "Welcome back", bo dawniej `effectiveEndDate` (fallback na
    /// daty przystanków, gdy user nie wypełnił dat całej podróży) był
    /// wystarczający. Teraz wymaga PRAWDZIWEJ, jawnie ustawionej daty
    /// końca podróży (`endDate` wprost, bez fallbacku) — user musiał
    /// faktycznie zaplanować/wypełnić kiedy podróż się kończy, nie
    /// przypadkowa data jednego przystanku.
    var justCompleted: Bool {
        guard let end = endDate, end < Date() else { return false }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: end), to: calendar.startOfDay(for: Date())).day ?? 0
        return days >= 0 && days <= 7
    }
}
