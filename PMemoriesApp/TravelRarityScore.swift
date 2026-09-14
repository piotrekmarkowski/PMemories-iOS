import CoreLocation

/// "Rarity Score" — 12.09.2026, feedback narzeczonej usera (przekazany przez
/// usera, dwie wiadomości): plakat "My Travel Journey" musi skalować się
/// DANYMI, nie GĘSTOŚCIĄ. Przy 80 krajach nie da się pokazać 80 pieczątek
/// ani 80 pinezek — trzeba wybrać NAJBARDZIEJ interesujące/rzadkie miejsca
/// ("travel bragging rights" — Bhutan/Mongolia/Antarktyda, nie kolejna
/// Francja/Hiszpania/Włochy), nie pierwsze z brzegu.
///
/// Hierarchia z wiadomości usera (uproszczona do policzalnego wzoru, bez
/// ręcznej bazy "jak rzadki jest każdy z ~200 krajów" — niemożliwa do
/// utrzymania i tak samo arbitralna jak zgadywanie): dystans od domu
/// (dominujący czynnik — dalej = rzadziej odwiedzane miejsce dla
/// przeciętnego podróżnika) + bonus za inny kontynent niż dom (kraj
/// sąsiedni ale na innym kontynencie liczy się bardziej niż daleki, ale
/// wciąż "swój" kontynent). "Ulubione" (najwyższy priorytet w oryginalnej
/// liście) świadomie POMINIĘTE — appka nie ma jeszcze takiej flagi w
/// danych, user potwierdził że nie trzeba jej teraz dodawać.
enum TravelRarityScore {
    /// Odległość Haversine w km — appka gdzie indziej (`JourneyStats`) nie
    /// liczy dystansu z surowych współrzędnych (ma już `legDistanceKm` na
    /// każdym przystanku), ale ranking rzadkości potrzebuje dystansu OD
    /// DOMU do KONKRETNEGO miejsca, nie sumy przelotów całej trasy.
    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let earthRadiusKm = 6371.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Kontynent dla kodu kraju — działa też dla podregionów UK ("GB-ENG"
    /// itd., appka dzieli Wielką Brytanię na 4 "kraje" gdzie indziej,
    /// patrz `TravelAchievementsCalculator.countryGroupingCode`) przez
    /// obcięcie do części przed myślnikiem.
    static func continent(for countryCode: String) -> String? {
        let base = countryCode.split(separator: "-").first.map(String.init) ?? countryCode
        return continentByCountryCode[base.uppercased()]
    }

    /// Wyższy wynik = rzadszy/bardziej "bragging rights" kierunek.
    /// `distanceKm/1000 * 3` dominuje ranking (Bhutan/Nowa Zelandia/
    /// Antarktyda naturalnie wygrywają z Francją/Hiszpanią dla usera z
    /// bazą w UK), `+15` za inny kontynent niż dom dodatkowo premiuje
    /// prawdziwą różnorodność geograficzną, nie tylko surowy dystans
    /// (np. RPA vs Rosja — podobny dystans od UK, ale RPA to inny
    /// kontynent).
    ///
    /// 12.09.2026, user uzupełnił hierarchię o dwa NIŻSZE priorytety niż
    /// dystans/kontynent (pkt 5-6 z oryginalnej listy): `isFavorite`
    /// (+8 — user ręcznie oznaczył podróż jako ulubioną w `TripsListView`)
    /// i `visitDate` (do +3, liniowo zanikające przez 3 lata — "najnowsze
    /// odwiedzone" jako najsłabszy czynnik, tylko rozstrzyga remisy
    /// pomiędzy podobnie rzadkimi miejscami, nigdy nie przebija dystansu
    /// ani kontynentu).
    static func score(
        coordinate: CLLocationCoordinate2D, countryCode: String?, home: CLLocationCoordinate2D, homeContinent: String?,
        isFavorite: Bool = false, visitDate: Date? = nil, referenceDate: Date = Date()
    ) -> Double {
        var value = distanceKm(coordinate, home) / 1000 * 3
        if let countryCode, let c = continent(for: countryCode), c != homeContinent {
            value += 15
        }
        if isFavorite {
            value += 8
        }
        if let visitDate {
            let years = referenceDate.timeIntervalSince(visitDate) / (365.25 * 24 * 3600)
            value += max(0, 3 - years)
        }
        return value
    }

    /// EU=Europa, AS=Azja, AF=Afryka, NA=Ameryka Płn., SA=Ameryka Płd.,
    /// OC=Oceania, AN=Antarktyda. Pokrywa wszystkie kody z
    /// `journeyStampAssetByCountryCode` (11.09.2026) + drobne terytoria z
    /// `worldStickerAssetByCountryCode`. Klasyfikacja przybliżona (np.
    /// Rosja/Turcja/Kazachstan jako Azja — geograficznie transkontynentalne,
    /// ale to tylko miękki bonus w rankingu, nie twierdzenie geograficzne).
    static let continentByCountryCode: [String: String] = [
        // Europa
        "AD": "EU", "AL": "EU", "AT": "EU", "BA": "EU", "BE": "EU", "BG": "EU",
        "BY": "EU", "CH": "EU", "CY": "EU", "CZ": "EU", "DE": "EU", "DK": "EU",
        "EE": "EU", "ES": "EU", "FI": "EU", "FR": "EU", "GB": "EU", "GR": "EU",
        "HR": "EU", "HU": "EU", "IE": "EU", "IS": "EU", "IT": "EU", "LI": "EU",
        "LT": "EU", "LU": "EU", "LV": "EU", "MC": "EU", "MD": "EU", "ME": "EU",
        "MK": "EU", "MT": "EU", "NL": "EU", "NO": "EU", "PL": "EU", "PT": "EU",
        "RO": "EU", "RS": "EU", "SE": "EU", "SI": "EU", "SK": "EU", "SM": "EU",
        "UA": "EU", "VA": "EU", "XK": "EU",

        // Azja (w tym transkontynentalne RU/TR/KZ/AZ/GE/CY liczone tu)
        "AE": "AS", "AF": "AS", "AM": "AS", "AZ": "AS", "BD": "AS", "BH": "AS",
        "BN": "AS", "BT": "AS", "CN": "AS", "GE": "AS", "ID": "AS", "IL": "AS",
        "IN": "AS", "IQ": "AS", "IR": "AS", "JO": "AS", "JP": "AS", "KG": "AS",
        "KH": "AS", "KP": "AS", "KR": "AS", "KW": "AS", "KZ": "AS", "LA": "AS",
        "LB": "AS", "LK": "AS", "MM": "AS", "MN": "AS", "MV": "AS", "MY": "AS",
        "NP": "AS", "OM": "AS", "PH": "AS", "PK": "AS", "PS": "AS", "QA": "AS",
        "RU": "AS", "SA": "AS", "SG": "AS", "SY": "AS", "TH": "AS", "TJ": "AS",
        "TL": "AS", "TM": "AS", "TR": "AS", "TW": "AS", "UZ": "AS", "VN": "AS",
        "YE": "AS",

        // Afryka
        "AO": "AF", "BF": "AF", "BI": "AF", "BJ": "AF", "BW": "AF", "CD": "AF",
        "CF": "AF", "CG": "AF", "CI": "AF", "CM": "AF", "CV": "AF", "DJ": "AF",
        "DZ": "AF", "EG": "AF", "EH": "AF", "ER": "AF", "ET": "AF", "GA": "AF",
        "GH": "AF", "GM": "AF", "GN": "AF", "GQ": "AF", "GW": "AF", "KE": "AF",
        "KM": "AF", "LR": "AF", "LS": "AF", "LY": "AF", "MA": "AF", "MG": "AF",
        "ML": "AF", "MR": "AF", "MU": "AF", "MW": "AF", "MZ": "AF", "NA": "AF",
        "NE": "AF", "NG": "AF", "RW": "AF", "SC": "AF", "SD": "AF", "SL": "AF",
        "SN": "AF", "SO": "AF", "SS": "AF", "ST": "AF", "SZ": "AF", "TD": "AF",
        "TG": "AF", "TN": "AF", "TZ": "AF", "UG": "AF", "YT": "AF", "ZA": "AF",
        "ZM": "AF", "ZW": "AF",

        // Ameryka Północna (w tym Karaiby/Ameryka Środkowa)
        "AG": "NA", "AI": "NA", "AW": "NA", "BB": "NA", "BL": "NA", "BM": "NA",
        "BQ": "NA", "BS": "NA", "BZ": "NA", "CA": "NA", "CR": "NA", "CU": "NA",
        "CW": "NA", "DM": "NA", "DO": "NA", "GD": "NA", "GL": "NA", "GT": "NA",
        "HN": "NA", "HT": "NA", "JM": "NA", "KN": "NA", "KY": "NA", "LC": "NA",
        "MF": "NA", "MQ": "NA", "MX": "NA", "NI": "NA", "PA": "NA", "PM": "NA",
        "PR": "NA", "SV": "NA", "TT": "NA", "US": "NA", "VC": "NA", "VG": "NA",
        "VI": "NA",

        // Ameryka Południowa
        "AR": "SA", "BO": "SA", "BR": "SA", "CL": "SA", "CO": "SA", "EC": "SA",
        "FK": "SA", "GF": "SA", "GY": "SA", "PE": "SA", "PY": "SA", "SR": "SA",
        "UY": "SA", "VE": "SA",

        // Oceania
        "AS": "OC", "AU": "OC", "CK": "OC", "FJ": "OC", "FM": "OC", "GU": "OC",
        "KI": "OC", "MH": "OC", "NC": "OC", "NR": "OC", "NU": "OC", "NZ": "OC",
        "PF": "OC", "PG": "OC", "PW": "OC", "SB": "OC", "TO": "OC", "TV": "OC",
        "VU": "OC", "WF": "OC", "WS": "OC",

        // Antarktyda / odosobnione terytoria
        "AQ": "AN", "GS": "AN", "IO": "AN", "SH": "AF", "TF": "AN",
    ]
}
