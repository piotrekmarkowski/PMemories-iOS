import Foundation

/// Jedna odznaka Travel Achievements — TYLKO dane które appka faktycznie zna
/// z zapisanych podróży (dystans per środek transportu, liczba krajów/miast/
/// lotów, wysokość) — ta sama zasada co "Lifetime Travel Stats" (`Travel.md`):
/// zero szacowanego czasu podróży, zero zgadywania. Progi (`milestones`) to
/// kolejne poziomy tej samej odznaki (np. "Kraje" 1→5→10→25→50), nie osobne
/// odznaki — user odblokowuje kolejne poziomy tym samym paskiem postępu.
/// Jeden wiersz listy szczegółów po tapnięciu odznaki (user 30.07.2026:
/// "klikamy kraje wyświetla się lista krajów, klikamy miasta lista miast
/// itd") — złożone z tych samych, już zapisanych pól `SavedStop`/`SavedTrip`,
/// zero nowych danych.
struct AchievementDetailRow: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let subtitle: String?
    let trailing: String?
}

struct Achievement: Identifiable {
    /// Uniwersalne nazwy poziomów, wspólne dla WSZYSTKICH kategorii odznak —
    /// user 30.07.2026 zasugerował tematyczne nazwy per kategoria (np.
    /// "Explorer I/II/III" dla krajów), ale appka ma odznaki bardzo różnego
    /// typu (kraje, ale też "Samochodem"/"Rejsy") — jeden tematyczny zestaw
    /// nie pasowałby wszędzie. Medale (Brąz/Srebro/Złoto/Platyna/Diament) są
    /// neutralne i skalują się na dowolną liczbę progów (2 do 5 dziś).
    static let tierNames = ["Bronze", "Silver", "Gold", "Platinum", "Diamond"]

    let id: String
    let emoji: String
    let title: String
    let unit: String
    /// Rzeczownik w dopełniaczu liczby mnogiej do tekstu progresu (np.
    /// "krajów", "miast") — tylko dla odznak liczbowych (`unit == ""`);
    /// `nil` dla km/m, gdzie `unit` już wystarcza ("Jeszcze 500 km").
    let detailNoun: String?
    let milestones: [Double]
    let currentValue: Double
    let detailRows: [AchievementDetailRow]

    var unlockedCount: Int {
        milestones.filter { currentValue >= $0 }.count
    }

    var isUnlocked: Bool { unlockedCount > 0 }

    var currentMilestone: Double? {
        milestones.filter { currentValue >= $0 }.max()
    }

    var nextMilestone: Double? {
        milestones.first { currentValue < $0 }
    }

    var isMaxed: Bool { nextMilestone == nil }

    var currentTierName: String? {
        guard unlockedCount > 0, unlockedCount - 1 < Self.tierNames.count else { return nil }
        return L(Self.tierNames[unlockedCount - 1])
    }

    var nextTierName: String? {
        guard nextMilestone != nil, unlockedCount < Self.tierNames.count else { return nil }
        return L(Self.tierNames[unlockedCount])
    }

    var progressToNext: Double {
        guard let next = nextMilestone else { return 1 }
        let previous = currentMilestone ?? 0
        guard next > previous else { return 1 }
        return min(1, max(0, (currentValue - previous) / (next - previous)))
    }

    func formatted(_ value: Double) -> String {
        let rounded = unit == "km" || unit == "m" ? value.rounded() : value
        let asInt = Int(rounded)
        return unit.isEmpty ? "\(asInt)" : "\(asInt) \(unit)"
    }

    /// "Jeszcze 5 krajów do poziomu Złoto" zamiast suchego "5 / 10" — user
    /// 30.07.2026. Bez nazwy poziomu (odznaka na maksymalnym poziomie już
    /// zdobytym powyżej listy medali) po prostu pomija tę część.
    var progressMessage: String? {
        guard let next = nextMilestone else { return nil }
        let remaining = max(0, next - currentValue)
        let amountText = detailNoun != nil ? "\(Int(remaining.rounded())) \(L(detailNoun!))" : formatted(remaining)
        guard let tierName = nextTierName else { return "\(amountText) \(L("to go"))" }
        return "\(amountText) \(L("until")) \(tierName)"
    }
}

/// "Around the World" — user 30.07.2026: MUSI być na pierwszym miejscu,
/// osobno od reszty odznak. Rosnący MNOŻNIK (2.4×, 5.1× dookoła świata), NIE
/// pasek 0-100% który się "kończy" po jednym okrążeniu — dokładnie ta sama
/// korekta usera, którą wcześniej zapisano w `Travel.md` przy oryginalnym
/// pomyśle Lifetime Stats, teraz faktycznie wdrożona. Liczone z SUMY
/// dystansu wszystkich odcinków wszystkich podróży (każdy środek transportu
/// razem, nie tylko jeden) — obwód Ziemi na równiku ≈ 40 075 km.
struct AroundTheWorldStat {
    static let earthCircumferenceKm: Double = 40_075

    let totalDistanceKm: Double

    var multiplier: Double { totalDistanceKm / Self.earthCircumferenceKm }
    var lapsCompleted: Int { Int(multiplier) }
    /// Postęp w TRWAJĄCYM okrążeniu (od ostatniego pełnego do następnego
    /// pełnego) — jedyne miejsce gdzie ma sens pasek 0-100%, bo nie
    /// "kończy" mnożnika, tylko pokazuje ruch w jego obrębie.
    var progressToNextLap: Double { multiplier - Double(lapsCompleted) }
    /// Ile km zostało do kolejnego pełnego okrążenia — user 30.07.2026:
    /// bardziej widowiskowy tekst niż sam pasek postępu ("Next milestone:
    /// 40 075 km").
    var remainingKmToNextLap: Double {
        Self.earthCircumferenceKm * (1 - progressToNextLap)
    }
}

/// "Explorer Score" — user 30.07.2026 wybrał prosty, DETERMINISTYCZNY
/// wskaźnik zamiast czekać na prawdziwą warstwę AI (`AI.md`, Etap 3,
/// świadomie zablokowany do czasu skończenia Travel — patrz `AI nigdy nie
/// blokuje wejść` w pamięci projektu). Świadomie NIE nazwane "AI" w UI mimo
/// nazwy z backlogu — appka nie ma dziś żadnej infrastruktury AI/ML, a
/// nazywanie zwykłego wzoru punktowego "AI" byłoby mylące. Jawny, czytelny
/// wzór (nie czarna skrzynka) — każdy składnik widoczny w rozbiciu po
/// tapnięciu karty (`ExplorerScoreBreakdownRow`). Waga celowo faworyzuje
/// RÓŻNORODNOŚĆ (kraje, różne środki transportu) nad samym dystansem — to
/// pasuje do ducha "explorer" bardziej niż nagradzanie kogoś kto poleciał
/// wiele razy w to samo miejsce.
struct ExplorerScore {
    static let tierNames = ["Newcomer", "Traveller", "Explorer", "Globetrotter", "Legend"]
    static let tierFloors: [Double] = [0, 50, 150, 350, 700]

    struct Component: Identifiable {
        let id: String
        let label: String
        let points: Double
    }

    let components: [Component]
    /// Prawdziwy, DOKŁADNY dystans (nie punkty) — user 13.08.2026: "dlaczego
    /// w rankingu pokazuje 40000 km a na pierwszej stronie 39,955?".
    /// Przyczyna: `LeaderboardService` wcześniej wysyłał `rawKm`
    /// odtworzone z ZAOKRĄGLONYCH punktów `distance` (`(totalKm / 100)
    /// .rounded() * 100` — celowo zgrubne dla punktacji, ale ZUPEŁNIE złe
    /// jako wyświetlana liczba km). To pole niesie ORYGINALNY, dokładny
    /// dystans obok punktów, żeby ranking mógł pokazywać PRAWDZIWĄ liczbę.
    let totalKm: Double

    var total: Double { components.reduce(0) { $0 + $1.points } }

    var tierName: String {
        let index = Self.tierFloors.lastIndex { total >= $0 } ?? 0
        return L(Self.tierNames[index])
    }

    /// Próg następnego poziomu — `nil` na "Legenda" (bez sufitu, jak Around
    /// the World — user 30.07.2026: nie chce sztucznych "max poziom" tam,
    /// gdzie w rzeczywistości nie ma górnej granicy).
    var nextTierFloor: Double? {
        Self.tierFloors.first { total < $0 }
    }
}

extension TravelAchievementsCalculator {
    static func explorerScore(from trips: [SavedTrip]) -> ExplorerScore {
        let allStops = trips.flatMap(\.stops)
        let stopsWithRealLeg = allStops.filter { $0.order > 0 && $0.legDistanceKm > 0 }

        let countryCount = Double(Set(allStops.compactMap(\.countryCode)).count)
        let cityCount = Double(Set(
            allStops.map { $0.cityName.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        ).count)
        let distinctTransportModes = Double(Set(stopsWithRealLeg.map(\.transportRawValue)).count)
        let totalKm = allStops.reduce(0) { $0 + $1.legDistanceKm }
        let hikingKm = stopsWithRealLeg
            .filter { $0.transportRawValue == TransportMode.hiking.rawValue }
            .reduce(0) { $0 + $1.legDistanceKm }
        let elevationGain = allStops.compactMap(\.elevationGainMeters).reduce(0, +)
        let highestPeak = allStops.compactMap(\.highestElevationMeters).max() ?? 0

        return ExplorerScore(components: [
            .init(id: "countries", label: "\(L("Countries")) (\(Int(countryCount)) × 20)", points: countryCount * 20),
            .init(id: "cities", label: "\(L("Cities")) (\(Int(cityCount)) × 5)", points: cityCount * 5),
            .init(id: "transportModes", label: "\(L("Modes of transport")) (\(Int(distinctTransportModes)) × 25)", points: distinctTransportModes * 25),
            .init(id: "distance", label: "\(L("Distance")) (\(Int(totalKm).formatted()) km ÷ 100)", points: (totalKm / 100).rounded()),
            .init(id: "hiking", label: "\(L("Hiking")) (\(Int(hikingKm).formatted()) km × 1)", points: hikingKm),
            .init(id: "elevation", label: "\(L("Elevation gain")) (\(Int(elevationGain).formatted()) m ÷ 100)", points: (elevationGain / 100).rounded()),
            .init(id: "peak", label: highestPeak > 0 ? "\(L("Highest peak")) (\(Int(highestPeak)) m ÷ 100)" : L("Highest peak"), points: (highestPeak / 100).rounded()),
        ], totalKm: totalKm)
    }

    /// "Travel Passport" — jedna "pieczątka" per odwiedzony kraj (grupowanie
    /// po `countryCode`, ten sam wzorzec co `countryRows` w `achievements`,
    /// ale z datą PIERWSZEJ wizyty zamiast liczby miast — to bardziej pasuje
    /// do stempla paszportowego: "kiedy pierwszy raz tu byłeś", nie "ile
    /// miast odwiedziłeś"). Posortowane chronologicznie (najstarsza pieczątka
    /// pierwsza), jak prawdziwy paszport.
    static func passportCountries(from trips: [SavedTrip]) -> [PassportCountry] {
        let allStops = trips.flatMap(\.stops)
        var byCode: [String: (name: String, firstVisit: Date?)] = [:]
        for stop in allStops {
            guard let code = stop.countryCode else { continue }
            let existing = byCode[code]
            let earliest: Date?
            switch (existing?.firstVisit, stop.arrivalDate) {
            case (nil, let new): earliest = new
            case (let old, nil): earliest = old
            case (let old?, let new?): earliest = min(old, new)
            }
            byCode[code] = (stop.country ?? existing?.name ?? code, earliest)
        }
        return byCode.map { code, value in
            PassportCountry(countryCode: code, countryName: value.name, firstVisitDate: value.firstVisit)
        }.sorted { lhs, rhs in
            switch (lhs.firstVisitDate, rhs.firstVisitDate) {
            case (let l?, let r?): return l < r
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}

struct PassportCountry: Identifiable {
    var id: String { countryCode }
    let countryCode: String
    let countryName: String
    let firstVisitDate: Date?
}

/// Ukryte odznaki (13.08.2026, user: "wprowadźmy lokalnie ukryte odznaki")
/// — świadomie BINARNE (odblokowana/nie), bez progów jak reszta `Achievement`,
/// i świadomie NIEPOKAZYWANE dopóki nieodblokowane (prawdziwa niespodzianka,
/// nie "??? do zdobycia" jak reguralne odznaki) — patrz `AchievementsView`.
/// Wszystkie liczone z JUŻ zapisanych `SavedTrip`/`SavedStop`, zero nowych
/// danych/zgadywania.
struct HiddenBadge: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let subtitle: String
}

extension TravelAchievementsCalculator {
    /// `projects` (13.08.2026, druga runda) — TYLKO do odznak liczących
    /// gotowe Memories (`SavedProject.exportedAssetIdentifier != nil` —
    /// niedokończony/niewyeksportowany projekt się nie liczy).
    static func hiddenBadges(from trips: [SavedTrip], projects: [SavedProject]) -> [HiddenBadge] {
        var badges: [HiddenBadge] = []
        let allStops = trips.flatMap(\.stops)

        // "Nocny Marek" — przyjazd gdzieś między północą a 4 rano (godzina
        // z `arrivalDate`, tak jak zapisana — appka nie przelicza stref
        // czasowych, to zabawna odznaka, nie naukowy pomiar).
        let hasNightArrival = allStops.contains { stop in
            guard let date = stop.arrivalDate else { return false }
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 4
        }
        if hasNightArrival {
            badges.append(HiddenBadge(
                id: "nightOwl", emoji: "🦉", title: L("Night Owl"),
                subtitle: L("Arrived somewhere between midnight and 4am")
            ))
        }

        // "Przekroczenie równika" — dwa KOLEJNE przystanki (po `order`) w
        // TEJ SAMEJ podróży z różnymi znakami szerokości geograficznej —
        // prawdziwe przekroczenie w trakcie trasy, nie tylko "był kiedyś na
        // północy i kiedyś na południu" w niepowiązanych podróżach.
        let crossedEquator = trips.contains { trip in
            let sorted = trip.stops.sorted { $0.order < $1.order }
            guard sorted.count >= 2 else { return false }
            for index in 1..<sorted.count {
                let previousLat = sorted[index - 1].latitude
                let currentLat = sorted[index].latitude
                if previousLat != 0, currentLat != 0, (previousLat > 0) != (currentLat > 0) {
                    return true
                }
            }
            return false
        }
        if crossedEquator {
            badges.append(HiddenBadge(
                id: "equatorCrosser", emoji: "🌐", title: L("Equator Crosser"),
                subtitle: L("Travelled from one hemisphere to the other")
            ))
        }

        // "Lot ptaka" — pojedynczy odcinek lotem dłuższy niż 10 000 km.
        let hasLongHaulFlight = allStops.contains {
            $0.transportRawValue == TransportMode.plane.rawValue && $0.legDistanceKm > 10_000
        }
        if hasLongHaulFlight {
            badges.append(HiddenBadge(
                id: "birdsFlight", emoji: "🦅", title: L("Bird's Flight"),
                subtitle: L("A single flight over 10,000 km")
            ))
        }

        // "Globtroter"/"Skoczek miejski" — liczone PER PODRÓŻ (nie suma
        // życiowa jak zwykłe odznaki Kraje/Miasta) — chodzi o RÓŻNORODNOŚĆ
        // JEDNEGO wyjazdu, nie o łączny dorobek.
        let hasMultiCountryTrip = trips.contains { Set($0.stops.compactMap(\.countryCode)).count >= 3 }
        if hasMultiCountryTrip {
            badges.append(HiddenBadge(
                id: "globetrotter", emoji: "🌎", title: L("Globetrotter"),
                subtitle: L("3 or more countries in a single trip")
            ))
        }

        let hasMultiCityTrip = trips.contains {
            Set($0.stops.map { $0.cityName.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }).count >= 5
        }
        if hasMultiCityTrip {
            badges.append(HiddenBadge(
                id: "cityHopper", emoji: "🏙️", title: L("City Hopper"),
                subtitle: L("5 or more cities in a single trip")
            ))
        }

        // "Powrót w 24h" — DOWOLNE dwa przystanki (nie tylko kolejne) w TEJ
        // SAMEJ podróży z tą samą nazwą miasta i różnicą dat przyjazdu
        // poniżej doby — realny "wyskoczyłem i wróciłem tego samego dnia".
        let hasQuickReturn = trips.contains { trip in
            let stops = trip.stops.filter { $0.arrivalDate != nil && !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }
            for i in 0..<stops.count {
                for j in (i + 1)..<stops.count {
                    let nameA = stops[i].cityName.trimmingCharacters(in: .whitespaces).lowercased()
                    let nameB = stops[j].cityName.trimmingCharacters(in: .whitespaces).lowercased()
                    guard nameA == nameB, let dateA = stops[i].arrivalDate, let dateB = stops[j].arrivalDate else { continue }
                    if abs(dateA.timeIntervalSince(dateB)) <= 24 * 3600 { return true }
                }
            }
            return false
        }
        if hasQuickReturn {
            badges.append(HiddenBadge(
                id: "aroundTheBlock", emoji: "🔄", title: L("Around the Block"),
                subtitle: L("Returned to the same place within 24 hours")
            ))
        }

        // Odznaki Memories — TYLKO gotowe, wyeksportowane projekty (patrz
        // komentarz przy sygnaturze funkcji).
        let exportedProjects = projects.filter { $0.exportedAssetIdentifier != nil }
        if !exportedProjects.isEmpty {
            badges.append(HiddenBadge(
                id: "memoryMaker", emoji: "🎬", title: L("Memory Maker"),
                subtitle: L("Created your first Memory")
            ))
        }
        if exportedProjects.contains(where: { project in
            project.items.contains { !$0.isVideo } && project.items.contains { $0.isVideo } && project.musicPersistentID != nil
        }) {
            badges.append(HiddenBadge(
                id: "directorsCut", emoji: "🎞️", title: L("Director's Cut"),
                subtitle: L("A Memory with photos, video, and music together")
            ))
        }
        if exportedProjects.contains(where: { $0.items.count >= 100 }) {
            badges.append(HiddenBadge(
                id: "theCollector", emoji: "📸", title: L("The Collector"),
                subtitle: L("A Memory with 100 or more photos and videos")
            ))
        }
        if exportedProjects.count >= 10 {
            badges.append(HiddenBadge(
                id: "storyteller", emoji: "✨", title: L("Storyteller"),
                subtitle: L("Created 10 Memories")
            ))
        }
        // "Archiwista" — Memories powiązane z 5+ RÓŻNYMI podróżami
        // (`SavedStop.linkedProjectID`, ten sam link co World Globe/Travel
        // Replay) — świadectwo wracania do appki między wyjazdami, nie
        // samej liczby filmów.
        if trips.filter({ trip in trip.stops.contains { $0.linkedProjectID != nil } }).count >= 5 {
            badges.append(HiddenBadge(
                id: "archivist", emoji: "🗄️", title: L("Archivist"),
                subtitle: L("Memories linked from 5 different trips")
            ))
        }

        return badges
    }
}

/// "Travel Wrapped" — roczne podsumowanie, styl Spotify Wrapped
/// (`Travel.md`: "Year in Review / Travel Wrapped"). Przypisanie podróży do
/// roku: jeśli którykolwiek przystanek ma `arrivalDate` (prawdziwa data
/// pobytu), używamy roku NAJWCZEŚNIEJSZEGO takiego przystanku — dopiero gdy
/// CAŁA podróż nie ma żadnej daty przyjazdu, spada do roku `createdAt`
/// (kiedy zapisana w appce) jako uczciwy fallback, nie zgadywanie.
struct TravelWrapped {
    let year: Int
    let tripCount: Int
    let countryCount: Int
    let cityCount: Int
    let totalKm: Double
    let topTrip: (title: String, km: Double)?
}

extension TravelAchievementsCalculator {
    private static func year(of trip: SavedTrip) -> Int {
        let earliestArrival = trip.stops.compactMap(\.arrivalDate).min()
        return Calendar.current.component(.year, from: earliestArrival ?? trip.createdAt)
    }

    /// Lata posortowane malejąco (najnowszy pierwszy) — do pickera w UI.
    static func wrappedYears(from trips: [SavedTrip]) -> [Int] {
        Array(Set(trips.map(year(of:)))).sorted(by: >)
    }

    static func wrapped(for targetYear: Int, from trips: [SavedTrip]) -> TravelWrapped {
        let yearTrips = trips.filter { year(of: $0) == targetYear }
        let yearStops = yearTrips.flatMap(\.stops)
        let countryCount = Set(yearStops.compactMap(\.countryCode)).count
        let cityCount = Set(
            yearStops.map { $0.cityName.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        ).count
        let totalKm = yearStops.reduce(0) { $0 + $1.legDistanceKm }
        let topTrip = yearTrips.max { $0.totalDistanceKm < $1.totalDistanceKm }
            .map { (title: $0.title, km: $0.totalDistanceKm) }

        return TravelWrapped(
            year: targetYear, tripCount: yearTrips.count, countryCount: countryCount,
            cityCount: cityCount, totalKm: totalKm, topTrip: topTrip
        )
    }
}

/// Uwaga: świadomie NIE ma tu odznak "100 Beaches"/"UNESCO Explorer" z
/// pierwotnej listy pomysłów w `Travel.md` — appka nie ma żadnego źródła
/// danych rozpoznającego plaże/miejsca UNESCO, a zgadywanie zniszczyłoby
/// zaufanie do reszty statystyk (ta sama zasada co brak szacowanego czasu
/// podróży). Dodać dopiero jeśli pojawi się realne źródło danych.
enum TravelAchievementsCalculator {
    static func aroundTheWorld(from trips: [SavedTrip]) -> AroundTheWorldStat {
        AroundTheWorldStat(totalDistanceKm: trips.flatMap(\.stops).reduce(0) { $0 + $1.legDistanceKm })
    }

    static func achievements(from trips: [SavedTrip]) -> [Achievement] {
        let allStops = trips.flatMap(\.stops)

        // Przystanek startowy KAŻDEJ trasy (`order == 0`) nie ma odcinka do
        // niego — `StopRow` celowo ukrywa dla niego picker "Dotarłeś"
        // (`TravelMapView.swift`, `if !isFirst`), bo nie da się nim dotrzeć
        // ŻADNYM środkiem transportu, to punkt wyjściowy. `TripStop.transport`
        // ma jednak domyślną wartość `.plane` (nigdy realnie ustawioną przez
        // usera dla startu), która trafia do `SavedStop.transportRawValue`
        // przy zapisie — bez tego filtra miasto startowe podróży samochodem
        // (np. Zakopane) błędnie liczyło się jako "Lot". `legDistanceKm == 0`
        // dla startu to ten sam sygnał z drugiej strony, więc dodatkowo
        // wyklucza WSZYSTKIE przystanki bez realnego, zmierzonego odcinka —
        // znaleziony 30.07.2026 na realnych danych usera (Zakopane, Tías).
        let stopsWithRealLeg = allStops.filter { $0.order > 0 && $0.legDistanceKm > 0 }

        func distance(forRawValues rawValues: Set<String>) -> Double {
            stopsWithRealLeg
                .filter { rawValues.contains($0.transportRawValue) }
                .reduce(0) { $0 + $1.legDistanceKm }
        }

        func stops(forRawValues rawValues: Set<String>) -> [SavedStop] {
            stopsWithRealLeg
                .filter { rawValues.contains($0.transportRawValue) }
                .sorted { ($0.arrivalDate ?? .distantPast) < ($1.arrivalDate ?? .distantPast) }
        }

        func dateText(_ stop: SavedStop) -> String? {
            stop.arrivalDate?.formatted(date: .abbreviated, time: .omitted)
        }

        func transportRows(_ rawValues: Set<String>) -> [AchievementDetailRow] {
            stops(forRawValues: rawValues).map { stop in
                AchievementDetailRow(
                    emoji: CityGeocoder.flagEmoji(countryCode: stop.countryCode),
                    title: CityGeocoder.shortenedAirportName(stop.cityName, coordinate: stop.coordinate),
                    subtitle: dateText(stop),
                    trailing: stop.legDistanceKm > 0 ? "\(Int(stop.legDistanceKm.rounded()).formatted()) km" : nil
                )
            }
        }

        // Kraje — grupowanie po `countryCode`, jeden wiersz per kraj z liczbą
        // odwiedzonych miast w tym kraju (nie jeden wiersz per przystanek).
        let countryRows: [AchievementDetailRow] = {
            var byCode: [String: (name: String, cities: Set<String>)] = [:]
            for stop in allStops {
                guard let code = stop.countryCode else { continue }
                let cityKey = stop.cityName.trimmingCharacters(in: .whitespaces)
                byCode[code, default: (stop.country ?? code, [])].cities.insert(cityKey)
            }
            return byCode.sorted { $0.value.name < $1.value.name }.map { code, value in
                AchievementDetailRow(
                    emoji: CityGeocoder.flagEmoji(countryCode: code),
                    title: value.name,
                    subtitle: value.cities.count == 1 ? L("1 city") : "\(value.cities.count) \(L("cities"))",
                    trailing: nil
                )
            }
        }()

        // Miasta — dedup po znormalizowanej nazwie, zachowuje pierwsze
        // spotkane oryginalne wielkie/małe litery do wyświetlenia.
        let cityRows: [AchievementDetailRow] = {
            var seen = Set<String>()
            var rows: [AchievementDetailRow] = []
            for stop in allStops.sorted(by: { ($0.arrivalDate ?? .distantPast) < ($1.arrivalDate ?? .distantPast) }) {
                let name = stop.cityName.trimmingCharacters(in: .whitespaces)
                let key = name.lowercased()
                guard !name.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                rows.append(AchievementDetailRow(
                    emoji: CityGeocoder.flagEmoji(countryCode: stop.countryCode),
                    title: name,
                    subtitle: stop.country,
                    trailing: dateText(stop)
                ))
            }
            return rows
        }()

        let tripRows: [AchievementDetailRow] = trips
            .sorted { $0.createdAt < $1.createdAt }
            .map { trip in
                AchievementDetailRow(
                    emoji: "🗺️",
                    title: trip.title,
                    subtitle: trip.createdAt.formatted(date: .abbreviated, time: .omitted),
                    trailing: trip.totalDistanceKm > 0 ? "\(Int(trip.totalDistanceKm.rounded()).formatted()) km" : nil
                )
            }

        let peakRows: [AchievementDetailRow] = allStops
            .filter { $0.highestElevationMeters != nil }
            .sorted { ($0.highestElevationMeters ?? 0) > ($1.highestElevationMeters ?? 0) }
            .map { stop in
                AchievementDetailRow(
                    emoji: "⛰️",
                    title: stop.cityName,
                    subtitle: dateText(stop),
                    trailing: "\(Int((stop.highestElevationMeters ?? 0).rounded()).formatted()) m"
                )
            }

        let elevationRows: [AchievementDetailRow] = allStops
            .filter { $0.elevationGainMeters != nil }
            .sorted { ($0.elevationGainMeters ?? 0) > ($1.elevationGainMeters ?? 0) }
            .map { stop in
                AchievementDetailRow(
                    emoji: "🧗",
                    title: stop.cityName,
                    subtitle: dateText(stop),
                    trailing: "+\(Int((stop.elevationGainMeters ?? 0).rounded()).formatted()) m"
                )
            }

        let countryCount = Double(Set(allStops.compactMap(\.countryCode)).count)
        let cityCount = Double(cityRows.count)
        let flightCount = Double(stopsWithRealLeg.filter { $0.transportRawValue == TransportMode.plane.rawValue }.count)
        let carKm = distance(forRawValues: [TransportMode.car.rawValue])
        let trainKm = distance(forRawValues: [TransportMode.train.rawValue])
        let waterKm = distance(forRawValues: [TransportMode.boat.rawValue, TransportMode.cruise.rawValue])
        let hikingKm = distance(forRawValues: [TransportMode.hiking.rawValue])
        let highestPeak = allStops.compactMap(\.highestElevationMeters).max() ?? 0
        let totalElevationGain = allStops.compactMap(\.elevationGainMeters).reduce(0, +)
        let tripCount = Double(trips.count)
        let cruiseCount = Double(stopsWithRealLeg.filter { $0.transportRawValue == TransportMode.cruise.rawValue }.count)

        // Progi podniesione 30.07.2026 — user: obawa, że ktoś odbije sufit
        // ("Maksymalny poziom") mając wciąż realnie dużo świata do zobaczenia.
        // "Kraje" to JEDYNA kategoria z prawdziwym, twardym sufitem w
        // rzeczywistości — 195 (193 państwa uznawane przez ONZ + Watykan +
        // Palestyna jako obserwatorzy) — top próg ustawiony na tę liczbę, więc
        // nikt nie "skończy" tej odznaki przed odwiedzeniem naprawdę
        // wszystkiego. Reszta kategorii nie ma naturalnego sufitu (km/loty/
        // szczyty), więc progi podniesione z zapasem tak, żeby zdobycie
        // najwyższego poziomu wymagało bycia naprawdę wyjątkowym podróżnikiem
        // (rekordziści-globtroterzy, nie "kilka fajnych wakacji").
        return [
            Achievement(id: "countries", emoji: "🌐", title: L("Countries"), unit: "", detailNoun: "countries",
                        milestones: [5, 25, 50, 100, 195], currentValue: countryCount, detailRows: countryRows),
            Achievement(id: "cities", emoji: "🏙️", title: L("Cities"), unit: "", detailNoun: "cities",
                        milestones: [10, 50, 150, 300, 500], currentValue: cityCount, detailRows: cityRows),
            Achievement(id: "flights", emoji: "✈️", title: L("Flights"), unit: "", detailNoun: "flights",
                        milestones: [5, 25, 75, 200, 500], currentValue: flightCount,
                        detailRows: transportRows([TransportMode.plane.rawValue])),
            Achievement(id: "trips", emoji: "🗺️", title: L("Trips"), unit: "", detailNoun: "trips",
                        milestones: [5, 20, 50, 100, 250], currentValue: tripCount, detailRows: tripRows),
            Achievement(id: "car", emoji: "🚗", title: L("By Car"), unit: "km", detailNoun: nil,
                        milestones: [500, 2500, 10000, 50000, 150000], currentValue: carKm,
                        detailRows: transportRows([TransportMode.car.rawValue])),
            Achievement(id: "train", emoji: "🚆", title: L("By Train"), unit: "km", detailNoun: nil,
                        milestones: [200, 1000, 5000, 20000, 75000], currentValue: trainKm,
                        detailRows: transportRows([TransportMode.train.rawValue])),
            Achievement(id: "water", emoji: "⛴️", title: L("By Water"), unit: "km", detailNoun: nil,
                        milestones: [100, 500, 2000, 8000, 25000], currentValue: waterKm,
                        detailRows: transportRows([TransportMode.boat.rawValue, TransportMode.cruise.rawValue])),
            Achievement(id: "cruise", emoji: "🛳️", title: L("Cruises"), unit: "", detailNoun: "cruises",
                        milestones: [1, 3, 8, 20, 50], currentValue: cruiseCount,
                        detailRows: transportRows([TransportMode.cruise.rawValue])),
            Achievement(id: "hiking", emoji: "🥾", title: L("Hiking"), unit: "km", detailNoun: nil,
                        milestones: [20, 100, 400, 1500, 5000], currentValue: hikingKm,
                        detailRows: transportRows([TransportMode.hiking.rawValue])),
            // Szczyt: naturalny sufit to Everest (8849 m) — top próg
            // ustawiony na wysokość najwyższego punktu na Ziemi.
            Achievement(id: "peak", emoji: "⛰️", title: L("Highest Peak"), unit: "m", detailNoun: nil,
                        milestones: [1500, 3000, 4500, 6000, 8849], currentValue: highestPeak, detailRows: peakRows),
            Achievement(id: "elevation", emoji: "🧗", title: L("Total Elevation Gain"), unit: "m", detailNoun: nil,
                        milestones: [1000, 5000, 20000, 75000, 250000], currentValue: totalElevationGain, detailRows: elevationRows),
        ]
    }
}
