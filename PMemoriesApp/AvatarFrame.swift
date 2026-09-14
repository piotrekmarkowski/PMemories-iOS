import SwiftUI

/// Katalog ramek/odznak awatara do wyboru przez usera (28-29.08.2026,
/// mockup usera z 10 tematycznymi ramkami — "takie ramki wprowadzamy...
/// mają wyglądać dokładnie tak samo"). Founder/Tester (`TesterRegistry.
/// Badge`) mają PIERWSZEŃSTWO i własny, stały wygląd — ten wybór dotyczy
/// tylko zwykłych userów (`badge == .none`).
///
/// Świadomie dostępne dla WSZYSTKICH już teraz, bez bramki Premium — appka
/// nie ma jeszcze systemu płatności (user wybrał wprost: "cały picker
/// teraz, bez blokady Premium" zamiast czekać na Premium albo pokazywać
/// kłódki). Premium jako osobny, trzeci poziom rozróżnienia zostaje w
/// `Docs/TODO.md` do czasu aż Premium faktycznie powstanie.
///
/// Kolory PRÓBKOWANE programowo (Python/PIL/`colorsys`, szukanie
/// najbardziej nasyconego piksela w pierścieniu każdego awatara) z
/// obrazka referencyjnego usera, nie dobrane "na oko" — stąd nietypowe,
/// bardzo konkretne wartości hex zamiast okrągłych liczb.
enum AvatarFrame: String, CaseIterable, Identifiable, Codable {
    case none
    case explorer, adventurer, globetrotter, dreamer, storyteller
    case photographer, wanderer, navigator, collector, memoryKeeper
    #if DEBUG
    // Sezonowe ramki (30.08.2026) — ilustrowane PNG assety
    // (`Seasonal*.imageset`), zupełnie inny styl niż programowe
    // `AvatarFrameOverlay` powyżej (Mikołaj/palma/dynia — nie da się
    // tego narysować kodem). User: "chce je mieć dostępne tak gdzie są
    // pozostałe ramki [w appce, do podglądu]... pamiętaj że jak będziemy
    // robić update one nie będą tam załączone". `#if DEBUG` zamiast
    // samego zapamiętania — Release/TestFlight builduje się bez tego
    // bloku w ogóle, więc fizycznie nie może trafić do App Store nawet
    // przez pomyłkę. NIE odblokowane dla zwykłych testerów (Debug builds
    // to tylko lokalne instalacje z Xcode), zniknie z pickera samo przy
    // najbliższym prawdziwym uploadzie.
    case seasonalBeachLover, seasonalIslandHopper, seasonalSunsetChaser
    case seasonalChristmasTraveler, seasonalWinterExplorer, seasonalChristmasMemories
    case seasonalSpookyTraveler, seasonalNightExplorer
    case seasonalLoveMemories, seasonalNewYearTraveller

    // Druga generacja ilustrowanych ramek PNG (05.09.2026, `PremiumBadge*`
    // assety, `Docs/TODO.md` "Druga generacja obwódek PNG") — user chce je
    // widzieć w tym samym pickerze do podglądu, tym samym mechanizmem
    // `#if DEBUG` co zestaw sezonowy wyżej. Docelowa kategoryzacja
    // (Founder wyłącznie dla twórcy, reszta w Premium) NIE jest tu jeszcze
    // wymuszona — to tylko podgląd, bramka dostępu to osobny krok.
    case badgeFounder, badgeTester, badgeExplorer, badgeAdventurer, badgeGlobetrotter
    case badgeDreamer, badgeStoryteller, badgePhotographer, badgeWanderer, badgeNavigator
    case badgeCollector, badgeMemoryKeeper, badgePremiumUser
    case badgeNewYear, badgeValentines, badgeBirthday, badgeChristmas, badgeHalloween
    case badgeEaster, badgeSummerVibes, badgeWinterExplorer, badgeHoneymoon, badgeCongratulations
    case badgeBabyArrival, badgeAnniversary, badgeTravelMilestone, badgeAchievement, badgeLimitedEdition
    #endif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L("No Frame")
        case .explorer: return L("Explorer")
        case .adventurer: return L("Adventurer")
        case .globetrotter: return L("Globetrotter")
        case .dreamer: return L("Dreamer")
        case .storyteller: return L("Storyteller")
        case .photographer: return L("Photographer")
        case .wanderer: return L("Wanderer")
        case .navigator: return L("Navigator")
        case .collector: return L("Collector")
        case .memoryKeeper: return L("Memory Keeper")
        #if DEBUG
        case .seasonalBeachLover: return "Beach Lover"
        case .seasonalIslandHopper: return "Island Hopper"
        case .seasonalSunsetChaser: return "Sunset Chaser"
        case .seasonalChristmasTraveler: return "Christmas Traveler"
        case .seasonalWinterExplorer: return "Winter Explorer"
        case .seasonalChristmasMemories: return "Christmas Memories"
        case .seasonalSpookyTraveler: return "Spooky Traveler"
        case .seasonalNightExplorer: return "Night Explorer"
        case .seasonalLoveMemories: return "Love & Memories"
        case .seasonalNewYearTraveller: return "New Year Traveller"
        // Bez dopisku "(Premium)" (05.09.2026, user: "te ramki nie powinny
        // mieć napisu (Premium) w nazwie jeśli Premium jest już pokazane
        // przez sekcję/badge") — sekcja w `AvatarFrameView` ma już własny
        // nagłówek "Premium", dopisek w KAŻDEJ nazwie był zbędny i mylił z
        // darmowym "Explorer" z siatki wyżej.
        case .badgeFounder: return "Founder"
        case .badgeTester: return "Tester"
        case .badgeExplorer: return "Explorer"
        case .badgeAdventurer: return "Adventurer"
        case .badgeGlobetrotter: return "Globetrotter"
        case .badgeDreamer: return "Dreamer"
        case .badgeStoryteller: return "Storyteller"
        case .badgePhotographer: return "Photographer"
        case .badgeWanderer: return "Wanderer"
        case .badgeNavigator: return "Navigator"
        case .badgeCollector: return "Collector"
        case .badgeMemoryKeeper: return "Memory Keeper"
        case .badgePremiumUser: return "Premium User"
        case .badgeNewYear: return "New Year"
        case .badgeValentines: return "Valentine's"
        case .badgeBirthday: return "Birthday"
        case .badgeChristmas: return "Christmas"
        case .badgeHalloween: return "Halloween"
        case .badgeEaster: return "Easter"
        case .badgeSummerVibes: return "Summer Vibes"
        case .badgeWinterExplorer: return "Winter Explorer"
        case .badgeHoneymoon: return "Honeymoon"
        case .badgeCongratulations: return "Congratulations"
        case .badgeBabyArrival: return "Baby Arrival"
        case .badgeAnniversary: return "Anniversary"
        case .badgeTravelMilestone: return "Travel Milestone"
        case .badgeAchievement: return "Achievement"
        case .badgeLimitedEdition: return "Limited Edition"
        #endif
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// Dla ramek PNG (`assetName != nil`) to tylko kolor pomocniczy przy
    /// zaznaczeniu w pickerze — sam wygląd bierze się z obrazka, nie z
    /// tego koloru.
    var color: Color {
        switch self {
        case .none: return .clear
        case .explorer: return Self.rgb(0x31, 0xC6, 0xEB)
        case .adventurer: return Self.rgb(0x82, 0xF3, 0x7A)
        case .globetrotter: return Self.rgb(0x0D, 0xBB, 0xFE)
        case .dreamer: return Self.rgb(0x7F, 0x45, 0xCF)
        case .storyteller: return Self.rgb(0xCB, 0x12, 0x5C)
        case .photographer: return Self.rgb(0xF2, 0x7F, 0x21)
        case .wanderer: return Self.rgb(0xFA, 0xD4, 0x11)
        case .navigator: return Self.rgb(0x56, 0x6F, 0xF1)
        case .collector: return Self.rgb(0x10, 0xCA, 0xDC)
        case .memoryKeeper: return Self.rgb(0xDA, 0x3F, 0x88)
        #if DEBUG
        case .seasonalBeachLover, .seasonalIslandHopper, .seasonalSunsetChaser,
             .seasonalChristmasTraveler, .seasonalWinterExplorer, .seasonalChristmasMemories,
             .seasonalSpookyTraveler, .seasonalNightExplorer,
             .seasonalLoveMemories, .seasonalNewYearTraveller,
             .badgeFounder, .badgeTester, .badgeExplorer, .badgeAdventurer, .badgeGlobetrotter,
             .badgeDreamer, .badgeStoryteller, .badgePhotographer, .badgeWanderer, .badgeNavigator,
             .badgeCollector, .badgeMemoryKeeper, .badgePremiumUser,
             .badgeNewYear, .badgeValentines, .badgeBirthday, .badgeChristmas, .badgeHalloween,
             .badgeEaster, .badgeSummerVibes, .badgeWinterExplorer, .badgeHoneymoon, .badgeCongratulations,
             .badgeBabyArrival, .badgeAnniversary, .badgeTravelMilestone, .badgeAchievement, .badgeLimitedEdition:
            return Palette.blue
        #endif
        }
    }

    var iconName: String? {
        switch self {
        case .none: return nil
        case .explorer: return "paperplane.fill"
        case .adventurer: return "mountain.2.fill"
        case .globetrotter: return "globe"
        case .dreamer: return "cloud.fill"
        case .storyteller: return "pencil"
        case .photographer: return "camera.fill"
        case .wanderer: return "signpost.right.fill"
        case .navigator: return "safari.fill"
        case .collector: return "bookmark.fill"
        case .memoryKeeper: return "heart.fill"
        #if DEBUG
        case .seasonalBeachLover, .seasonalIslandHopper, .seasonalSunsetChaser,
             .seasonalChristmasTraveler, .seasonalWinterExplorer, .seasonalChristmasMemories,
             .seasonalSpookyTraveler, .seasonalNightExplorer,
             .seasonalLoveMemories, .seasonalNewYearTraveller,
             .badgeFounder, .badgeTester, .badgeExplorer, .badgeAdventurer, .badgeGlobetrotter,
             .badgeDreamer, .badgeStoryteller, .badgePhotographer, .badgeWanderer, .badgeNavigator,
             .badgeCollector, .badgeMemoryKeeper, .badgePremiumUser,
             .badgeNewYear, .badgeValentines, .badgeBirthday, .badgeChristmas, .badgeHalloween,
             .badgeEaster, .badgeSummerVibes, .badgeWinterExplorer, .badgeHoneymoon, .badgeCongratulations,
             .badgeBabyArrival, .badgeAnniversary, .badgeTravelMilestone, .badgeAchievement, .badgeLimitedEdition:
            return nil
        #endif
        }
    }

    #if DEBUG
    /// Tylko sezonowe ramki mają gotowy obrazek — reszta katalogu jest
    /// rysowana programowo (`AvatarFrameOverlay`, `color`/`iconName`
    /// wyżej). `nil` dla wszystkich innych przypadków.
    var assetName: String? {
        switch self {
        case .seasonalBeachLover: return "SeasonalBeachLover"
        case .seasonalIslandHopper: return "SeasonalIslandHopper"
        case .seasonalSunsetChaser: return "SeasonalSunsetChaser"
        case .seasonalChristmasTraveler: return "SeasonalChristmasTraveler"
        case .seasonalWinterExplorer: return "SeasonalWinterExplorer"
        case .seasonalChristmasMemories: return "SeasonalChristmasMemories"
        case .seasonalSpookyTraveler: return "SeasonalSpookyTraveler"
        case .seasonalNightExplorer: return "SeasonalNightExplorer"
        case .seasonalLoveMemories: return "SeasonalLoveMemories"
        case .seasonalNewYearTraveller: return "SeasonalNewYearTraveller"
        case .badgeFounder: return "PremiumBadgeFounder"
        case .badgeTester: return "PremiumBadgeTester"
        case .badgeExplorer: return "PremiumBadgeExplorer"
        case .badgeAdventurer: return "PremiumBadgeAdventurer"
        case .badgeGlobetrotter: return "PremiumBadgeGlobetrotter"
        case .badgeDreamer: return "PremiumBadgeDreamer"
        case .badgeStoryteller: return "PremiumBadgeStoryteller"
        case .badgePhotographer: return "PremiumBadgePhotographer"
        case .badgeWanderer: return "PremiumBadgeWanderer"
        case .badgeNavigator: return "PremiumBadgeNavigator"
        case .badgeCollector: return "PremiumBadgeCollector"
        case .badgeMemoryKeeper: return "PremiumBadgeMemoryKeeper"
        case .badgePremiumUser: return "PremiumBadgePremiumUser"
        case .badgeNewYear: return "PremiumBadgeNewYear"
        case .badgeValentines: return "PremiumBadgeValentines"
        case .badgeBirthday: return "PremiumBadgeBirthday"
        case .badgeChristmas: return "PremiumBadgeChristmas"
        case .badgeHalloween: return "PremiumBadgeHalloween"
        case .badgeEaster: return "PremiumBadgeEaster"
        case .badgeSummerVibes: return "PremiumBadgeSummerVibes"
        case .badgeWinterExplorer: return "PremiumBadgeWinterExplorer"
        case .badgeHoneymoon: return "PremiumBadgeHoneymoon"
        case .badgeCongratulations: return "PremiumBadgeCongratulations"
        case .badgeBabyArrival: return "PremiumBadgeBabyArrival"
        case .badgeAnniversary: return "PremiumBadgeAnniversary"
        case .badgeTravelMilestone: return "PremiumBadgeTravelMilestone"
        case .badgeAchievement: return "PremiumBadgeAchievement"
        case .badgeLimitedEdition: return "PremiumBadgeLimitedEdition"
        default: return nil
        }
    }

    /// Maska PRAWDZIWEGO (nie kołowego) kształtu dziury — TYLKO dla drugiej
    /// generacji `PremiumBadge*` (05.09.2026, user: screenshot Globetrottera
    /// z globusem "zalanym" zdjęciem). Jeden uniwersalny okrąg nie mógł
    /// zadziałać dla asymetrycznych projektów (globus przesunięty w bok) —
    /// zamiast przybliżać geometrię, każdy z 28 assetów ma DODATKOWY,
    /// towarzyszący plik PNG z DOKŁADNIE wykrytym kształtem dziury (ten sam
    /// piksel-po-pikselu obszar co w `punch_circular_hole`/`find_hole_mask`
    /// przy wycinaniu), używany w SwiftUI przez `.mask()` zamiast
    /// `clipShape(Circle())`. `nil` dla starego zestawu sezonowego (bez
    /// wygenerowanej maski, zostaje przy kołowym przybliżeniu) i dla
    /// prostych, programowych ramek.
    var maskAssetName: String? {
        guard isPremiumBadge, let assetName else { return nil }
        return assetName + "Mask"
    }

    /// Mnożnik skali CAŁEJ kompozycji Premium (ring+maska+zdjęcie razem,
    /// 06.09.2026, user: zmierzył bezpośrednio na zrzucie ekranu, że
    /// darmowe ramki (rysowane wektorowo, wypełniają 100% `avatarSize`)
    /// wizualnie zajmują ~119px, a Premium (PNG z naturalnym przezroczystym
    /// marginesem wokół dekoracji) tylko ~95-101px na tej samej skali —
    /// realny rozjazd ~15-20%. Wyliczony z `visible bounding box` każdego
    /// PNG (ile z jego canvasu faktycznie zajmuje nieprzezroczysta grafika,
    /// zmierzone w audycie designu) tak, żeby po przeskalowaniu każdy asset
    /// zajmował ~98% karty — dopasowanie do konwencji darmowych ramek, nie
    /// arbitralne 90% z pierwszej, nieudanej próby tej normalizacji.
    var outerScale: Double {
        Self.premiumBadgeOuterScaleByRawValue[rawValue] ?? 1.0
    }

    private static let premiumBadgeOuterScaleByRawValue: [String: Double] = [
        "badgeFounder": 1.064, "badgeTester": 1.049, "badgeExplorer": 1.082,
        "badgeAdventurer": 1.11, "badgeDreamer": 1.133, "badgeStoryteller": 1.024,
        "badgePhotographer": 1.186, "badgeWanderer": 1.153, "badgeNavigator": 1.059,
        "badgeCollector": 1.104, "badgeMemoryKeeper": 1.046, "badgePremiumUser": 1.045,
        "badgeNewYear": 1.08, "badgeValentines": 1.099, "badgeBirthday": 1.125,
        "badgeChristmas": 1.084, "badgeHalloween": 1.038, "badgeEaster": 1.152,
        "badgeSummerVibes": 1.096, "badgeWinterExplorer": 1.125, "badgeHoneymoon": 1.119,
        "badgeCongratulations": 1.106, "badgeBabyArrival": 1.148, "badgeAnniversary": 1.065,
        "badgeTravelMilestone": 1.091, "badgeAchievement": 1.132, "badgeLimitedEdition": 1.08,
    ]

    /// Canvas assetu (340×340) względem promienia pierścienia (~100px,
    /// zmierzone na "Beach Lover") — ten sam mechanizm skalowania co
    /// dawne `overlayScaleFactor` dla neonowych ramek, tylko lokalny do
    /// sezonowego zestawu (reszta katalogu w ogóle go nie potrzebuje,
    /// stąd nie globalna stała).
    static let seasonalOverlayScaleFactor: Double = 340.0 / 200.0

    /// Mnożniki skali dla drugiej generacji `PremiumBadge*` (05.09.2026) —
    /// PO PRÓBIE spłaszczenia do jednego wspólnego mnożnika (jak w zestawie
    /// sezonowym) okazało się, że to matematycznie nie może zadziałać: skala
    /// CAŁEGO obrazka (resize) nie zmienia proporcji dziury do kanwy — user:
    /// "zdjecie nie jest wyciete idealnie... niektore strony sa ok a
    /// kolejne nie". Nasz zestaw ma NAPRAWDĘ różne proporcje dziury między
    /// ramkami (bardziej złożone kompozycje niż zestaw sezonowy, gdzie
    /// wszystkie 10 miały zbliżony układ) — jeden mnożnik pasuje dobrze
    /// tylko tym bliskim 1.7, dla reszty zdjęcie albo wystaje poza
    /// pierścień (Photographer 2.47×) albo zostaje w nim luka. Każdy
    /// obrazek zmierzony indywidualnie (Python/PIL/scipy, prawdziwy środek
    /// i średnica dziury) — stąd per-ramka wartości.
    private static let premiumBadgeScaleByRawValue: [String: Double] = [
        "badgeFounder": 1.697, "badgeTester": 1.925, "badgeExplorer": 1.842,
        "badgeAdventurer": 1.817, "badgeGlobetrotter": 1.686, "badgeDreamer": 1.883,
        "badgeStoryteller": 1.718, "badgePhotographer": 2.127, "badgeWanderer": 1.839,
        "badgeNavigator": 1.766, "badgeCollector": 1.857, "badgeMemoryKeeper": 1.681,
        "badgePremiumUser": 1.755, "badgeNewYear": 1.621, "badgeValentines": 1.516,
        "badgeBirthday": 1.553, "badgeChristmas": 1.629, "badgeHalloween": 1.547,
        "badgeEaster": 1.663, "badgeSummerVibes": 1.537, "badgeWinterExplorer": 1.546,
        "badgeHoneymoon": 1.538, "badgeCongratulations": 1.579, "badgeBabyArrival": 1.596,
        "badgeAnniversary": 1.459, "badgeTravelMilestone": 1.433, "badgeAchievement": 1.535,
        "badgeLimitedEdition": 1.446,
    ]

    /// Który mnożnik skali użyć dla TEGO assetu PNG — `AvatarFrameBadge`
    /// pyta o to zamiast trzymać osobne rozgałęzienie u siebie. Sezonowy
    /// zestaw (bliskie proporcje) dalej korzysta z jednej stałej.
    var overlayScaleFactor: Double {
        Self.premiumBadgeScaleByRawValue[rawValue] ?? Self.seasonalOverlayScaleFactor
    }


    /// Bounding box (ułamki 0...1 canvasu) PRAWDZIWEGO otworu na zdjęcie,
    /// zmierzony bezpośrednio z pliku maski `*Mask.png` (06.09.2026, user:
    /// zdjęcie ucinało głowę na pełnoportretowych zdjęciach w ramkach
    /// Premium — przyczyna: zdjęcie było dopasowywane `aspectRatio(.fill)`
    /// do PEŁNEJ karty 68×68, a otwór faktycznie zajmuje tylko 37-63% tej
    /// karty, więc "przybliżenie" wynikające z dopasowania do pełnej karty
    /// obcinało górę/dół kadru zanim maska w ogóle zadziałała). Używane
    /// przez `avatarFramedPhoto(_:size:)` do dopasowania zdjęcia do
    /// rzeczywistego rozmiaru otworu zamiast do całej karty.
    var holeRect: (x: Double, y: Double, width: Double, height: Double)? {
        Self.premiumBadgeHoleRectByRawValue[rawValue]
    }

    private static let premiumBadgeHoleRectByRawValue: [String: (x: Double, y: Double, width: Double, height: Double)] = [
        // 06.09.2026, druga aktualizacja — user pokazał na realnym pickerze
        // wyraźną szarą/białą "podkładkę" między zdjęciem a właściwym
        // pierścieniem na WSZYSTKICH ramkach. Zweryfikowane pikselowo
        // (test z syntetyczną szachownicą + render samego ringu BEZ zdjęcia,
        // który już pokazywał tę plamę): to nieprzezroczyste, prawie białe
        // piksele NAMALOWANE w oryginalnym PNG poza faktyczną dziurą — próg
        // wykrywania przezroczystości przy pierwszym wycinaniu assetów był
        // zbyt zachowawczy. Otwór rozszerzony na assetach (26 z 28 —
        // Navigator wyłączony, bo automatyczne rozszerzenie zjadało kotwicę
        // w jego dekoracji; Globetrotter usunięty z pickera) i te wartości
        // odzwierciedlają NOWY, większy, poprawny otwór.
        "badgeFounder": (x: 0.2237, y: 0.2138, width: 0.5461, height: 0.5362),
        "badgeTester": (x: 0.1224, y: 0.194, width: 0.6478, height: 0.5493),
        "badgeExplorer": (x: 0.129, y: 0.1806, width: 0.6419, height: 0.5774),
        "badgeAdventurer": (x: 0.2317, y: 0.1714, width: 0.6159, height: 0.581),
        "badgeGlobetrotter": (x: 0.2463, y: 0.3167, width: 0.5073, height: 0.3695),
        "badgeDreamer": (x: 0.0881, y: 0.2044, width: 0.6698, height: 0.5566),
        "badgeStoryteller": (x: 0.1779, y: 0.1994, width: 0.6196, height: 0.5521),
        "badgePhotographer": (x: 0.2583, y: 0.2492, width: 0.4835, height: 0.4565),
        "badgeWanderer": (x: 0.2625, y: 0.2065, width: 0.4808, height: 0.5457),
        "badgeNavigator": (x: 0.0779, y: 0.1526, width: 0.8344, height: 0.7175),
        "badgeCollector": (x: 0.0848, y: 0.1879, width: 0.6788, height: 0.5636),
        "badgeMemoryKeeper": (x: 0.093, y: 0.1728, width: 0.7641, height: 0.6312),
        "badgePremiumUser": (x: 0.2039, y: 0.1743, width: 0.6053, height: 0.5855),
        "badgeNewYear": (x: 0.1029, y: 0.1994, width: 0.7363, height: 0.6013),
        "badgeValentines": (x: 0.1951, y: 0.1777, width: 0.6376, height: 0.6551),
        "badgeBirthday": (x: 0.1854, y: 0.1954, width: 0.6325, height: 0.6093),
        "badgeChristmas": (x: 0.2062, y: 0.1753, width: 0.6735, height: 0.6014),
        "badgeHalloween": (x: 0.1979, y: 0.1944, width: 0.6806, height: 0.6181),
        "badgeEaster": (x: 0.1656, y: 0.1818, width: 0.6753, height: 0.5942),
        "badgeSummerVibes": (x: 0.116, y: 0.1843, width: 0.7645, height: 0.5939),
        "badgeWinterExplorer": (x: 0.1322, y: 0.1153, width: 0.7186, height: 0.6814),
        "badgeHoneymoon": (x: 0.0669, y: 0.194, width: 0.7793, height: 0.6522),
        "badgeCongratulations": (x: 0.202, y: 0.1919, width: 0.6465, height: 0.6263),
        "badgeBabyArrival": (x: 0.2013, y: 0.1981, width: 0.6429, height: 0.6331),
        "badgeAnniversary": (x: 0.1359, y: 0.1672, width: 0.7282, height: 0.6585),
        "badgeTravelMilestone": (x: 0.1877, y: 0.1877, width: 0.6621, height: 0.6416),
        "badgeAchievement": (x: 0.2114, y: 0.1544, width: 0.6477, height: 0.6477),
        "badgeLimitedEdition": (x: 0.1626, y: 0.1522, width: 0.7128, height: 0.654),
    ]

    /// Czy TA ramka należy do drugiej generacji `PremiumBadge*` (05.09.2026)
    /// — `AvatarFrameCard` tego używa żeby dać TYLKO tym ramkom większy,
    /// kompaktowo dobrany kontener. Realny bug (user: "nawet wczesniejsze
    /// ktore bylo ok sie pomniejszyly"): wcześniejszy warunek `assetName !=
    /// nil` obejmował TEŻ stary, już zaakceptowany zestaw sezonowy
    /// (`Seasonal*`), więc niechcący zmieniał jego sprawdzony rozmiar.
    /// Zestaw sezonowy ma zostać CAŁKOWICIE nietknięty.
    var isPremiumBadge: Bool {
        Self.premiumBadgeScaleByRawValue[rawValue] != nil
    }

    /// Rozróżnia 13 "postaciowych" ramek `PremiumBadge*` (Founder…Premium
    /// User — ulepszone wersje TYCH SAMYCH postaci co w darmowej siatce) od
    /// 15 okazjonalnych/sezonowych (New Year…Limited Edition) — user
    /// (05.09.2026): "Premium powinno wyglądać jak prawdziwy upgrade...
    /// Special/Occasional osobno". Rozróżnienie po `rawValue`, nie po
    /// osobnym zbiorze — te 13 są dokładnie case'ami zdefiniowanymi PRZED
    /// `badgeNewYear` w deklaracji enuma.
    var isSeasonalPremiumBadge: Bool {
        switch self {
        case .badgeNewYear, .badgeValentines, .badgeBirthday, .badgeChristmas, .badgeHalloween,
             .badgeEaster, .badgeSummerVibes, .badgeWinterExplorer, .badgeHoneymoon, .badgeCongratulations,
             .badgeBabyArrival, .badgeAnniversary, .badgeTravelMilestone, .badgeAchievement, .badgeLimitedEdition:
            return true
        default:
            return false
        }
    }

    /// Stary zestaw sezonowy (`seasonalBeachLover`…`seasonalNewYearTraveller`,
    /// 30.08.2026) — user 05.09.2026: pokazywał się w darmowej siatce obok
    /// prawdziwych darmowych ramek, mylący z NOWYM, ładniejszym zestawem
    /// `badgeNewYear`…`badgeLimitedEdition` (ta sama tematyka). Ukryty z
    /// katalogu (nie usunięty — assety zostają, na wypadek gdyby jednak
    /// się przydały).
    var isLegacySeasonalPreview: Bool {
        switch self {
        case .seasonalBeachLover, .seasonalIslandHopper, .seasonalSunsetChaser,
             .seasonalChristmasTraveler, .seasonalWinterExplorer, .seasonalChristmasMemories,
             .seasonalSpookyTraveler, .seasonalNightExplorer,
             .seasonalLoveMemories, .seasonalNewYearTraveller:
            return true
        default:
            return false
        }
    }

    #endif
}
