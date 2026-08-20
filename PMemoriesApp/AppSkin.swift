import SwiftUI

/// Skórka tła zakładek (Home/Studio/Travel/Library) — 02.08.2026, user:
/// "kazda zakladka jest teraz ciemna dobrze by bylo zeby miala skorke ale
/// nie taka co bedzie bardzo mieszac musi byc delikatna". User sam wybiera
/// skórkę w zakładce Templates (żadnego automatycznego rozpoznawania
/// lokalizacji na start — patrz decyzja w `Travel.md`/pamięci projektu:
/// "użytkownicy decydują w co ubierają appkę").
///
/// `.seasonal` jest wyjątkiem wśród reszty — to JEDYNA skórka, która sama
/// zmienia obrazek (wg aktualnej pory roku, patrz `Season.current`).
/// Pozostałe skórki są dziś pojedynczym, stałym obrazem (jeden motyw = jeden
/// plik w `Assets.xcassets`) — user chciałby żeby TEŻ się zmieniały w
/// obrębie danej zakładki dla urozmaicenia, ale to wymaga WIĘCEJ niż
/// jednego zdjęcia na motyw, których dziś nie mamy (tylko po jednym z
/// przesłanych obrazów koncepcyjnych) — świadomie odłożone, łatwe do
/// dodania później: `AppSkin.assetNames` już zwraca TABLICĘ, nie
/// pojedynczą nazwę, więc dorzucenie kolejnych zdjęć do motywu nie wymaga
/// zmiany architektury, tylko dodania plików.
enum AppSkin: String, CaseIterable, Identifiable, Codable {
    case none
    case seasonal
    case beach
    case mountains
    case city
    case forestWaterfall
    case roadTrip
    case globeTravel
    case nightSky
    case tropicalLagoon
    case desertDawn

    var id: String { rawValue }

    static var pickerCases: [AppSkin] { allCases }

    var displayName: String {
        switch self {
        case .none: return L("Default (no skin)")
        case .seasonal: return L("Seasonal")
        case .beach: return L("Beach")
        case .mountains: return L("Mountains")
        case .city: return L("City Lights")
        case .forestWaterfall: return L("Forest Waterfall")
        case .roadTrip: return L("Road Trip")
        case .globeTravel: return L("Around the World")
        case .nightSky: return L("Starry Night")
        case .tropicalLagoon: return L("Tropical Lagoon")
        case .desertDawn: return L("Desert Dawn")
        }
    }

    /// Obrazek(i) w Assets.xcassets — TABLICA nawet dla motywów z jednym
    /// dziś dostępnym zdjęciem (patrz komentarz przy typie), żeby dodanie
    /// kolejnych wariantów w przyszłości nie wymagało zmiany API.
    var assetNames: [String] {
        switch self {
        case .none: return []
        case .seasonal: return Season.allCases.map(\.assetName)
        case .beach: return ["SkinBeach"]
        case .mountains: return ["SkinMountains"]
        case .city: return ["SkinCity"]
        case .forestWaterfall: return ["SkinForestWaterfall"]
        case .roadTrip: return ["SkinRoadTrip"]
        case .globeTravel: return ["SkinGlobeTravel"]
        case .nightSky: return ["SkinNightSky"]
        case .tropicalLagoon: return ["SkinTropicalLagoon"]
        case .desertDawn: return ["SkinDesertDawn"]
        }
    }

    /// Miniaturka w pickerze Templates — dla `.seasonal` zawsze ta sama
    /// okładka (niezależnie od aktualnej pory roku), żeby wybór w gridzie
    /// był stabilny/przewidywalny, nie skakał w zależności od dnia.
    var thumbnailAssetName: String? {
        switch self {
        case .none: return nil
        case .seasonal: return "SkinSeasonalCover"
        default: return assetNames.first
        }
    }

    /// Obrazek do faktycznego wyświetlenia TERAZ w tle zakładki — dla
    /// `.seasonal` liczony z aktualnej daty+półkuli (`Season.current`), dla
    /// reszty zawsze jedyny dostępny wariant.
    var currentAssetName: String? {
        switch self {
        case .none: return nil
        case .seasonal: return Season.current().assetName
        default: return assetNames.first
        }
    }

    /// Szybki, bezstanowy odczyt wprost z `UserDefaults` (ten sam klucz co
    /// `@AppStorage("selectedAppSkin")` wszędzie indziej) — do użycia w
    /// miejscach gdzie deklarowanie pełnej właściwości `@AppStorage` nie ma
    /// sensu (np. wewnątrz złożonego, wielokolorowego `Text` jak
    /// "PlayMemories"/"PMemories", gdzie tylko JEDEN segment ma się zmienić,
    /// reszta zachowuje swój kolor marki).
    static var isAnySkinActive: Bool {
        let rawValue = UserDefaults.standard.string(forKey: "selectedAppSkin") ?? AppSkin.none.rawValue
        return AppSkin(rawValue: rawValue)?.currentAssetName != nil
    }
}

/// Pora roku do skórki `.seasonal` — liczona z kalendarza TELEFONU
/// (miesiąc) + regionu systemowego jako przybliżenie półkuli (user:
/// "tez trzeba to wziac pod uwage ;) jaki ma kalendarz w telefonie" —
/// świadomie NIE prawdziwa lokalizacja GPS, tylko `Locale.current.region`,
/// żeby appka nie musiała prosić o uprawnienia lokalizacji tylko dla tła).
enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    var assetName: String {
        switch self {
        case .spring: return "SkinSeasonSpring"
        case .summer: return "SkinSeasonSummer"
        case .autumn: return "SkinSeasonAutumn"
        case .winter: return "SkinSeasonWinter"
        }
    }

    /// Dopisane 10.08.2026 dla Seasonal Challenges (`SeasonalChallenge.swift`)
    /// — dotąd `Season` miała tylko nazwę assetu tła, nie tekst do pokazania
    /// userowi.
    var displayName: String {
        switch self {
        case .spring: return L("Spring")
        case .summer: return L("Summer")
        case .autumn: return L("Autumn")
        case .winter: return L("Winter")
        }
    }

    /// Meteorologiczne pory roku (miesiące kalendarzowe, nie astronomiczne
    /// przesilenia — prostsze i wystarczająco dokładne dla tła). Mapowanie
    /// dla PÓŁKULI PÓŁNOCNEJ — `current(...)` odwraca dla południowej.
    private static func northernHemisphereSeason(forMonth month: Int) -> Season {
        switch month {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter // 12, 1, 2
        }
    }

    private var oppositeAcrossHemispheres: Season {
        switch self {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }

    /// Kraje/regiony południowej półkuli — NIE wyczerpująca lista co do
    /// milimetra (kraje równikowe nie mają silnych pór roku, nieistotne dla
    /// tła), ale pokrywa realnie duże populacje na południowej półkuli.
    private static let southernHemisphereRegionCodes: Set<String> = [
        "AU", "NZ", "AR", "CL", "UY", "PY", "BO", "BR", "ZA", "ZW", "ZM",
        "MZ", "NA", "BW", "MG", "FJ", "PG", "PF"
    ]

    static func current(date: Date = Date(), regionCode: String? = Locale.current.region?.identifier) -> Season {
        let month = Calendar.current.component(.month, from: date)
        let base = northernHemisphereSeason(forMonth: month)
        if let regionCode, southernHemisphereRegionCodes.contains(regionCode) {
            return base.oppositeAcrossHemispheres
        }
        return base
    }

    /// Pierwszy dzień bieżącego sezonu (dla Seasonal Challenges,
    /// `SeasonalChallenge.swift`, 10.08.2026) — pory roku METEOROLOGICZNE,
    /// spójne z `current(...)`. Zima (start grudzień) wymaga cofnięcia roku
    /// gdy dziś jest styczeń/luty — sezon "zaczął się" w grudniu POPRZEDNIEGO
    /// roku kalendarzowego; ten sam rollover dotyczy odpowiednika na
    /// półkuli południowej (tam to lato zaczyna się w grudniu).
    static func currentRangeStart(date: Date = Date(), regionCode: String? = Locale.current.region?.identifier) -> Date {
        let calendar = Calendar.current
        let season = current(date: date, regionCode: regionCode)
        let isSouthern = regionCode.map { southernHemisphereRegionCodes.contains($0) } ?? false
        let startMonth: Int
        switch (season, isSouthern) {
        case (.spring, false): startMonth = 3
        case (.summer, false): startMonth = 6
        case (.autumn, false): startMonth = 9
        case (.winter, false): startMonth = 12
        case (.spring, true): startMonth = 9
        case (.summer, true): startMonth = 12
        case (.autumn, true): startMonth = 3
        case (.winter, true): startMonth = 6
        }
        var year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if month < startMonth { year -= 1 }
        return calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? date
    }
}
