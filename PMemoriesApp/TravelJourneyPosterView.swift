import SwiftUI
import MapKit
import SwiftData

/// "My Travel Journey" — udostępnialny plakat-scrapbook (05.09.2026, user
/// przesłał mockup: mapa świata z trasą, polaroidy z najważniejszych
/// podróży, statystyki, rząd pieczątek krajów). Świadomie ZERO nowych
/// grafik dekoracyjnych do wycinania — tło/taśma/ramki polaroidów rysowane
/// programowo w SwiftUI (ten sam duch co `AvatarFrameOverlay`), a mapa to
/// prawdziwy `MKMapSnapshotter` z pinezkami na faktycznie odwiedzonych
/// współrzędnych, nie ręcznie rysowana ilustracja kontynentów. Wszystkie
/// liczby (kraje/podróże/km/loty) POLICZONE z prawdziwych `SavedTrip`, ten
/// sam mechanizm grupowania krajów co `TravelWrapped`/Passport (Wielka
/// Brytania jako 4 osobne "kraje").
///
/// Przebudowa kompozycji (06.09.2026, user: "to nie ma wyglądać jak
/// dashboard, ma wyglądać jak dzieło sztuki" + długa lista konkretnych
/// problemów — ogromna pusta przestrzeń na dole, sekcje sztywno
/// poukładane, statystyki jak pasek UI, znaczki jak przyciski):
/// - Canvas ma teraz DYNAMICZNĄ wysokość (stała szerokość 1080, wysokość
///   wynika z faktycznej treści) zamiast sztywnych 1080×1920 z resztą
///   wypełnianą pustym `Spacer()`.
/// - Mapa/polaroidy/statystyki/pieczątki to jedna, nakładająca się
///   kompozycja (ujemny padding pozwala statystykom "wchodzić" na dolną
///   krawędź mapy), nie sekwencja rozłącznych sekcji.
/// - Statystyki wyglądają jak bilet/karta pokładowa (przerywana
///   perforacja, lekki obrót), nie pasek dashboardu.
/// - Pieczątki krajów są okrągłe z podwójną obwódką jak prawdziwy stempel
///   pocztowy, każda lekko obrócona, zamiast prostokątnych "przycisków".
/// - Tło to warstwowy gradient + programowo generowany szum/ziarno
///   (`paperGrain`), nie płaski dwukolorowy gradient.
/// ŚWIADOMIE bez zmiany logiki/danych — liczby, dobór zdjęć, nazwy miejsc
/// zostają dokładnie takie same jak przed przebudową.
struct TravelJourneyPosterView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]

    @State private var mapSnapshot: UIImage?
    /// Dzień/noc mapy (13.09.2026, przywrócone na wyraźną prośbę usera) —
    /// wybrane RAZ przy generowaniu plakatu, wg lokalnej godziny urządzenia
    /// (`Self.isDaytimeHour`), NIE losowane i NIE zależne od liczby zdjęć/
    /// krajów. Ustawiane w `.task` w tym samym momencie co reszta mapy,
    /// czytane zarówno przez `renderMapSnapshot` (wybór `traitCollection`
    /// Apple Maps) jak i przez widoki rysujące piny/trasy (`mapCard`,
    /// `flightPathOverlay`) — obie strony muszą się zgadzać, inaczej
    /// kolory podświetleń wylądowałyby na złej bazie mapy.
    @State private var isDaytimeMap = true
    @State private var mapPinPoints: [CGPoint] = []
    /// Trasa KAŻDEJ podróży osobno (11.09.2026, patrz `renderMapSnapshot`) —
    /// jedna pod-tablica punktów na podróż, w rzeczywistej kolejności
    /// zwiedzania. `flightPathOverlay` rysuje każdą osobno, żeby mapa
    /// pokazywała prawdziwą sieć podróży, nie fikcyjny "lot" między dwiema
    /// niepowiązanymi wycieczkami.
    @State private var mapRoutePaths: [[CGPoint]] = []
    /// Podświetlone odwiedzone kraje (12.09.2026, Warstwa 1 z feedbacku
    /// narzeczonej: "mapa jest zbyt pusta... podświetlone kraje = ogólna
    /// historia podróżowania, pinezki = konkretne wspomnienia"). Tylko
    /// kraje z realnymi przystankami — reszta świata zostaje wyblakła,
    /// bo taka już jest baza `.mutedStandard`, nie trzeba jej dorysowywać.
    /// Patrz `renderMapSnapshot`/`CountryFillShape`.
    @State private var countryFills: [CountryFillShape] = []
    @State private var polaroids: [PolaroidPhoto] = []
    @State private var isLoading = true
    @State private var isPreparingShare = false
    @State private var shareImage: IdentifiableImage?
    @State private var posterImage: UIImage?
    @State private var backgroundTextureName: String = TravelJourneyPosterView.paperTextureNames.randomElement()!
    /// Ręczne podmiany zdjęć per kraj (09.09.2026, user: "musi byc opcja
    /// wybierania zdjec... powinnismy miec opcje zmiany jesli nam sie ono
    /// nie podoba" — konkretny przypadek: Gatwick jako JEDYNE zdjęcie
    /// całej podróży, automatyczny dobór nie ma z czego wybrać lepszego).
    /// Trwałe w `UserDefaults` (nie SwiftData — to tylko preferencja
    /// wyświetlania plakatu, nie prawdziwe dane podróży), klucz = kod
    /// grupowania kraju, wartość = `PHAsset.localIdentifier`.
    @State private var photoOverrides: [String: String] = TravelJourneyPosterView.loadPhotoOverrides()
    @State private var isShowingPhotoCustomization = false

    private static let photoOverridesDefaultsKey = "travelJourneyPosterPhotoOverrides"

    private static func loadPhotoOverrides() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: photoOverridesDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private static func savePhotoOverrides(_ overrides: [String: String]) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        UserDefaults.standard.set(data, forKey: photoOverridesDefaultsKey)
    }

    private static let posterWidth: CGFloat = 1080

    /// 13.09.2026: user poprosił o prawdziwy wschód/zachód słońca (tak jak
    /// systemowy Dark Mode "Automatyczny"), nie sztywne 6:00-20:00. Próbuje
    /// jednorazowej lokalizacji (`CurrentLocationProvider`, ten sam
    /// mechanizm co rozpoznawanie szczytu w `PeakDetector`) + lokalny,
    /// offline wzór wschodu/zachodu (`SolarTime`, zero zależności
    /// sieciowej). Jeśli lokalizacja odmówiona/niedostępna/timeout —
    /// bezpieczny powrót do prostych progów godzinowych, żeby dzień/noc
    /// mapy NIGDY nie zablokowało generowania plakatu.
    private static func determineIsDaytimeMap() async -> Bool {
        let fallback: () -> Bool = {
            let hour = Calendar.current.component(.hour, from: Date())
            return (6..<20).contains(hour)
        }
        guard let location = try? await AsyncTimeout.run(seconds: 4, { try await CurrentLocationProvider.currentLocation() }),
              let sun = SolarTime.sunriseSunset(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, date: Date())
        else {
            return fallback()
        }
        let now = Date()
        return now >= sun.sunrise && now < sun.sunset
    }
    /// 13.09.2026, dziewiąta runda — REALNA przyczyna mapy "połykającej"
    /// statystyki (nie zgadywanie, potwierdzone debug-obramowaniem na
    /// żywo): `Image(...).aspectRatio(contentMode: .fill)` w SwiftUI ma
    /// UDOKUMENTOWANE zachowanie — gdy proporcje ŹRÓDŁOWEGO obrazu nie
    /// zgadzają się z proporcjami miejsca docelowego, wymiar potrzebny do
    /// pełnego pokrycia MOŻE przekroczyć to co zaproponował rodzic (Apple:
    /// "either dimension may be larger than the available space"). Mapa jest
    /// renderowana jako `options.size = 1000×800` (1.25:1), wyświetlana w
    /// boksie ~992×480 (2.07:1, dużo szerszym) — SwiftUI skalował obraz
    /// żeby pokryć szerokość, co dawało realną wysokość ~794pt zamiast 480
    /// — i BEZ `.clipped()` na WŁAŚCIWYM kontenerze ta nadwyżka malowała
    /// się na wierzchu statystyk. User: nie generować mapy w innych
    /// proporcjach (jakość/koszt bez potrzeby) — poprawny fix to
    /// `.clipped()` na dedykowanym kontenerze karty mapy (`mapCard`),
    /// NIE zmiana samego snapshotu. Stała wysokość w JEDNYM miejscu,
    /// współdzielona przez `mapSection`/`mapCard`, żeby nie rozjechała się
    /// znowu przy kolejnej zmianie.
    // 13.09.2026, jedenasta runda: user — mapa była kurczona przez kilka
    // rund (760→660→610→480), i dopóki `.fill` bez `.clipped()` sekretnie
    // "dopełniał" to nadmiarem malującym się NA statystykach (bug z
    // dziewiątej rundy), różnica była niewidoczna. Po poprawnym przycięciu
    // ta różnica stała się realną, odsłoniętą pustą przestrzenią między
    // mapą a statystykami. User: "przywróć mapie wcześniejszą wysokość,
    // jeśli to możliwe" (preferowane nad przesuwaniem elementów w dół) —
    // częściowy powrót 480→560, żeby wypełnić dziurę bez cofania całej
    // pracy nad zmniejszeniem mapy z poprzednich rund.
    // JEDENASTA runda (ciąg dalszy): częściowy powrót do 560 dalej za mało
    // — user porównał wprost z ostatnią wersją, którą sam potwierdził jako
    // poprawną (przed serią zmniejszeń mapy), i poprosił o PEŁNY powrót do
    // tamtej wysokości, nie częściowy. 610 to dokładnie ta wysokość — teraz
    // połączona z poprawnym `.clipped()` (fix z dziewiątej rundy), więc
    // mapa może bezpiecznie wrócić do pełnego rozmiaru bez ryzyka że
    // znowu "połknie" statystyki.
    private static let mapSectionHeight: CGFloat = 610

    /// 6 różnych, prawdziwych tekstur papieru (06.09.2026, user: "po to
    /// mamy tyle roznych rzeczy zeby tak wlasnie bylo i zeby sie nie
    /// powtarzaly u ludzi ktorzy to bedda robic") — losowana RAZ przy
    /// wejściu na ekran (`backgroundTextureName`, nie za każdym re-renderem
    /// SwiftUI), więc podgląd i eksport w TEJ SAMEJ sesji zawsze się
    /// zgadzają, ale różni userzy (i kolejne wizyty tego samego usera)
    /// dostają różne tło.
    // 13.09.2026, TYMCZASOWO na czas testu nowych teł scrapbookowych —
    // user przesłał 11 nowych wariantów, wybrałem 2 "bezpieczne" (bez
    // wypalonych fałszywych dat/pieczątek typu "DEPARTED LONDON 28 APR
    // 2024") do sprawdzenia na żywo jak wygląda nasza treść na wierzchu.
    // ORYGINALNA lista (6 zwykłych teksturek papieru) zostaje tutaj
    // zakomentowana, nie usunięta — łatwy powrót jeśli user zdecyduje że
    // stare tło było lepsze.
    // private static let paperTextureNames = [
    //     "TravelJourneyPaperTexture", "TravelJourneyPaperTexture2", "TravelJourneyPaperTexture3",
    //     "TravelJourneyPaperTexture4", "TravelJourneyPaperTexture5", "TravelJourneyPaperTexture6",
    // ]
    private static let paperTextureNames = [
        "PosterBackgroundScrapbookMono", "PosterBackgroundScrapbookColor",
    ]

    private var stats: JourneyStats {
        JourneyStats(from: savedTrips)
    }

    private var countryStamps: [CountryStamp] {
        var byCode: [String: CountryStamp] = [:]
        for stop in savedTrips.flatMap(\.stops) {
            guard let rawCode = stop.countryCode,
                  let code = TravelAchievementsCalculator.countryGroupingCode(countryCode: rawCode, administrativeArea: stop.administrativeArea)
            else { continue }
            // 12.09.2026: pierwsze trafienie per kraj wygrywa (jak dotąd),
            // ALE jeśli kolejny przystanek w TYM SAMYM kraju jest dalej od
            // domu, podmieniamy jego współrzędną na tę dalszą — przy
            // rankingu rzadkości (patrz `TravelRarityScore`) liczy się
            // NAJDALSZY punkt w danym kraju, nie przypadkowo pierwszy z
            // brzegu (np. lotnisko tranzytowe blisko granicy).
            // 12.09.2026: ulubiona podróż w TYM kraju "wygrywa" niezależnie
            // od dystansu — jeśli user oznaczył serduszkiem którykolwiek
            // pobyt w danym kraju, TEN pobyt reprezentuje kraj na
            // plakacie (żeby `isFavorite` faktycznie trafiał do rankingu,
            // nie ginął gdy przypadkiem przegrał z dystansem innego
            // przystanku w tym samym kraju).
            if let existing = byCode[code], let home = homeCoordinate {
                let stopIsFavorite = stop.trip?.isFavorite ?? false
                if stopIsFavorite && !existing.isFavorite {
                    byCode[code] = CountryStamp(code: code, name: existing.name, flag: existing.flag, coordinate: stop.coordinate, isFavorite: true, visitDate: stop.arrivalDate)
                } else if stopIsFavorite == existing.isFavorite
                    && TravelRarityScore.distanceKm(stop.coordinate, home) > TravelRarityScore.distanceKm(existing.coordinate, home) {
                    byCode[code] = CountryStamp(code: code, name: existing.name, flag: existing.flag, coordinate: stop.coordinate, isFavorite: existing.isFavorite, visitDate: stop.arrivalDate)
                }
                continue
            }
            let name = TravelAchievementsCalculator.countryGroupingDisplayName(countryCode: rawCode, administrativeArea: stop.administrativeArea, fallback: stop.country ?? code)
            byCode[code] = CountryStamp(
                code: code, name: name, flag: CityGeocoder.flagEmoji(countryCode: rawCode), coordinate: stop.coordinate,
                isFavorite: stop.trip?.isFavorite ?? false, visitDate: stop.arrivalDate
            )
        }
        return byCode.values.sorted { $0.name < $1.name }
    }

    /// "Dom" usera — wyliczony automatycznie, nie proszony wprost
    /// (12.09.2026, feedback narzeczonej o rarity score wymaga punktu
    /// odniesienia do liczenia dystansu). Najczęściej występujący
    /// przystanek startowy (`order == 0`) ze WSZYSTKICH podróży —
    /// zaokrąglony do ~11m (4 miejsca po przecinku), żeby to samo
    /// lotnisko wylotu z lekko różniącym się GPS-em liczyło się jako
    /// jeden "dom", nie dziesiątki prawie-identycznych. `nil` gdy appka
    /// nie zna żadnego przystanku startowego — ranking rzadkości wtedy
    /// po prostu nie działa (`countryStamps`/mapa spadają na kolejność
    /// nieposortowaną, zero zgadywania współrzędnych domu znikąd).
    private var homeCoordinate: CLLocationCoordinate2D? {
        let origins = savedTrips.compactMap { $0.stops.sorted { $0.order < $1.order }.first }
        guard !origins.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var representative: [String: CLLocationCoordinate2D] = [:]
        for stop in origins {
            let key = String(format: "%.4f,%.4f", stop.coordinate.latitude, stop.coordinate.longitude)
            counts[key, default: 0] += 1
            representative[key] = stop.coordinate
        }
        guard let mostCommonKey = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return representative[mostCommonKey]
    }

    private var homeContinent: String? {
        guard let home = homeCoordinate else { return nil }
        // Kod kraju domu = kraj najczęstszego przystanku startowego (ten
        // sam klucz co `homeCoordinate` wybrał), nie osobne wyliczenie —
        // unika rozjazdu gdyby dwa różne lotniska w tym samym kraju miały
        // podobną częstość.
        let origins = savedTrips.compactMap { $0.stops.sorted { $0.order < $1.order }.first }
        guard let match = origins.first(where: {
            abs($0.coordinate.latitude - home.latitude) < 0.0001 && abs($0.coordinate.longitude - home.longitude) < 0.0001
        }), let code = match.countryCode else { return nil }
        return TravelRarityScore.continent(for: code)
    }

    /// Sam kod kraju domu (nie kontynent) — do podświetlenia domu osobnym
    /// kolorem na mapie (`countryFills`). Ten sam mechanizm wyboru co
    /// `homeContinent`, tylko zwraca `countryCode` zamiast kontynentu.
    private var homeCountryCode: String? {
        guard let home = homeCoordinate else { return nil }
        let origins = savedTrips.compactMap { $0.stops.sorted { $0.order < $1.order }.first }
        return origins.first(where: {
            abs($0.coordinate.latitude - home.latitude) < 0.0001 && abs($0.coordinate.longitude - home.longitude) < 0.0001
        })?.countryCode
    }

    /// Kraje posortowane od NAJRZADSZYCH (najdalej od domu + bonus za inny
    /// kontynent) — `stampsRow`/`footer` tną tę listę do sensownej liczby
    /// zamiast pokazywać wszystkie (feedback narzeczonej: "80 countries →
    /// 80 pieczątek to katastrofa").
    private var rankedCountryStamps: [CountryStamp] {
        guard let home = homeCoordinate else { return countryStamps }
        let homeC = homeContinent
        return countryStamps.sorted {
            TravelRarityScore.score(coordinate: $0.coordinate, countryCode: $0.code, home: home, homeContinent: homeC, isFavorite: $0.isFavorite, visitDate: $0.visitDate) >
            TravelRarityScore.score(coordinate: $1.coordinate, countryCode: $1.code, home: home, homeContinent: homeC, isFavorite: $1.isFavorite, visitDate: $1.visitDate)
        }
    }

    /// Ile pieczątek pokazać W OGÓLE (12.09.2026, user: "≤12 → wszystkie,
    /// 13-25 → ~10-12, 25+ → jeszcze bardziej minimalistycznie") — reszta
    /// reprezentowana przez kafelek "+N MORE" w `stampsRow`.
    private var visibleStampCount: Int {
        let total = countryStamps.count
        if total <= 12 { return total }
        if total <= 25 { return 12 }
        return 10
    }

    /// Wybrane przez rarity score, ale wyświetlone w porządku alfabetycznym
    /// (czytelniej niż "od najdalszego") — ranking decyduje KTÓRE się
    /// zmieszczą, nie w jakiej kolejności je widać.
    private var displayedCountryStamps: [CountryStamp] {
        Array(rankedCountryStamps.prefix(visibleStampCount)).sorted { $0.name < $1.name }
    }

    private var hiddenStampCount: Int {
        max(0, countryStamps.count - visibleStampCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading || posterImage == nil {
                    ProgressView(L("Preparing your journey…"))
                        .frame(height: 400)
                } else if let posterImage {
                    // 07.09.2026, user: "dlaczego nie mam calego obrazu
                    // tylko musze ruszac palcem" — DWIE próby ze skalowaniem
                    // "na żywo" (`.fixedSize()` + `GeometryReader` do
                    // pomiaru wysokości + `.scaleEffect()`) kończyły się
                    // pustym ekranem, niezależnie od tego czy tło miało
                    // własny `GeometryReader` czy nie. Zamiast dalej walczyć
                    // z tym samym mechanizmem: plakat renderowany RAZ do
                    // zwykłego `UIImage` (ten sam `ImageRenderer` co przy
                    // eksporcie/share, patrz `renderPosterImage()`), potem
                    // pokazywany jako zwykłe zdjęcie przez
                    // `.resizable().scaledToFit()` — niezawodny, dobrze
                    // przetestowany mechanizm SwiftUI, zero ręcznej
                    // geometrii. Podgląd i eksport używają DOKŁADNIE tego
                    // samego rendera, więc zawsze wyglądają identycznie.
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 8)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("My Travel Journey"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 09.09.2026, user: "musi byc opcja wybierania zdjec" — jawny,
            // odkrywalny przycisk zamiast liczenia na to, że user domyśli
            // się dotknąć płaskiego, wyrenderowanego obrazka (który i tak
            // nie ma żadnych aktywnych stref dotyku, patrz `posterImage`).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingPhotoCustomization = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .disabled(isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await prepareShareImage() }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isLoading || isPreparingShare)
            }
        }
        .sheet(item: $shareImage) { wrapper in
            ActivityShareSheet(items: [wrapper.image])
        }
        .sheet(isPresented: $isShowingPhotoCustomization) {
            PosterPhotoCustomizationView(polaroids: polaroids.map { $0 as PosterPolaroidDescribable }) { code, identifier in
                photoOverrides[code] = identifier
                TravelJourneyPosterView.savePhotoOverrides(photoOverrides)
                Task {
                    polaroids = await loadPolaroids()
                    posterImage = renderPosterImage()
                }
            }
        }
        .task {
            // Sekwencyjnie (12.09.2026) — mapa musi znać KTÓRE podróże
            // dostarczyły polaroidy (`pics.compactMap(\.tripID)`), żeby
            // premiować dokładnie te same trasy/pinezki zamiast wybierać
            // niezależnie przez sam rarity score. Zero równoległości
            // (`async let`), ale to jednorazowe ładowanie plakatu, nie
            // ścieżka wrażliwa na czas.
            let pics = await loadPolaroids()
            // 13.09.2026: dzień/noc mapy wybrany RAZ, TERAZ — przed
            // wywołaniem `renderMapSnapshot` (który go czyta dla
            // `traitCollection`) i zanim jakikolwiek widok (piny/trasy)
            // zdąży się z nim rozjechać.
            isDaytimeMap = await Self.determineIsDaytimeMap()
            let snap = await renderMapSnapshot(priorityTripIDs: Set(pics.compactMap(\.tripID)))
            mapSnapshot = snap.image
            mapPinPoints = snap.points
            mapRoutePaths = snap.routePaths
            countryFills = snap.countryFills
            polaroids = pics
            posterImage = renderPosterImage()
            isLoading = false
        }
    }

    /// Jeden, wspólny render (07.09.2026) dla podglądu NA EKRANIE i dla
    /// udostępniania — oba muszą wyglądać identycznie, więc oba korzystają
    /// z DOKŁADNIE tego samego `UIImage`, wygenerowanego raz po załadowaniu
    /// mapy/zdjęć.
    /// 13.09.2026: wysokość BYŁA niewymuszona ("ImageRenderer sam dobiera
    /// wysokość do treści") — działało dobrze przy starych, bezszwowych
    /// teksturkach papieru (nie mają żadnej "kompozycji" do zachowania,
    /// można je przyciąć w dowolnym miejscu bez straty). Ale user zgłosił:
    /// nowe tła scrapbookowe to gotowe, jednorazowe ILUSTRACJE o STAŁYCH
    /// proporcjach (2:3) z elementami w konkretnych miejscach (kompas w
    /// rogu, sygnpost przy krawędzi) — `paperBackground`'s
    /// `.aspectRatio(contentMode: .fill)` naciągał/przycinał TĘ konkretną
    /// grafikę do wysokości wyliczonej z treści, więc górna/dolna warstwa
    /// tła się ucinała. Fix: wysokość całego plakatu wynika teraz z
    /// PRAWDZIWYCH proporcji pliku tła (`backgroundNativeAspectRatio`),
    /// nie z treści — więc `.fill` na tle staje się de facto no-opem
    /// (proporcje już się zgadzają, zero kadrowania/zoomu).
    @MainActor
    private func renderPosterImage() -> UIImage? {
        let height = Self.posterWidth / backgroundNativeAspectRatio
        // 13.09.2026, ósma runda: user zgłosił mapę nachodzącą na tytuł —
        // przyczyna: wysokość była wymuszona DWIEMA nakładającymi się
        // ścieżkami naraz (jawny `.frame(height:)` na treści ORAZ
        // `renderer.proposedSize`), co dawało niespójny wynik pomiaru
        // layoutu w `ImageRenderer`. Teraz TYLKO `proposedSize` ustala
        // wysokość — jedno źródło prawdy, bez podwójnego wymuszania.
        let renderer = ImageRenderer(content: posterContent.frame(width: Self.posterWidth))
        renderer.proposedSize = ProposedViewSize(width: Self.posterWidth, height: height)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Szerokość/wysokość PLIKU aktualnie wylosowanego tła (`UIImage(named:)`
    /// czyta wymiary bez dekodowania całego obrazu do pamięci) — 1.5 (2:3)
    /// jako bezpieczny fallback gdyby z jakiegoś powodu assetu nie dało się
    /// wczytać, żeby plakat nigdy nie wyrenderował się z wysokością zero.
    private var backgroundNativeAspectRatio: CGFloat {
        guard let size = UIImage(named: backgroundTextureName)?.size, size.height > 0 else { return 2.0 / 3.0 }
        return size.width / size.height
    }

    @MainActor
    private func prepareShareImage() async {
        guard let posterImage else { return }
        shareImage = IdentifiableImage(image: posterImage)
    }

    // MARK: - Poster layout (stała szerokość 1080, dynamiczna wysokość, jedna nakładająca się kompozycja)

    @ViewBuilder
    private var posterContent: some View {
        VStack(spacing: 0) {
            header
            // 13.09.2026, trzynasta runda: user (świeży zrzut) — kompas w
            // `decorativeDivider` (ostatni element nagłówka) jest lekko
            // ucięty przez górną krawędź mapy. Przyczyna: kompas ma
            // `.rotationEffect(-8°)` na ramce 34×34 — obrót NIE zmienia
            // rozmiaru liczonego przez layout, ale WIZUALNIE róg obróconego
            // kwadratu wystaje poza swój prostokąt; przy odstępie tylko
            // 6pt ten róg wchodził na mapę. Sam kompas/mapa bez zmian —
            // wystarczy więcej oddechu między nagłówkiem a mapą (6→22).
            mapSection
                .padding(.top, 22)
                // 11.09.2026, user: "dlaczego ta linia przechodzi po napisie
                // na zdjeciu" — zdjęcia CELOWO wychodzą poza dolną krawędź
                // mapy (`.offset()` w `mapSection`, nie wpływa na wysokość
                // layoutu), ale `statsPlaque` (kolejny element w tym samym
                // VStacku) renderuje się PO `mapSection`, więc w SwiftUI
                // maluje się NA WIERZCHU — jego obwódka (`strokeBorder`)
                // przecinała podpis polaroidu, który nachodził na jego
                // górny margines. `zIndex` trzyma całą mapę (razem z
                // overflow'ującymi zdjęciami) nad wszystkim co idzie dalej
                // w VStacku.
                .zIndex(1)
            // 13.09.2026, siódma runda: szósta runda przesadziła w drugą
            // stronę — user: "między mapą a znaczkami powstaje zbyt dużo
            // pustej przestrzeni... statystyki bliżej mapy". Skoro mapa
            // jest teraz WYRAŹNIE krótsza (patrz `mapSection`), nie trzeba
            // już aż tak dużego marginesu żeby uniknąć nachodzenia — 60→38.
            // ÓSMA runda: "mapa niemal dotyka liczb, dodaj 20-30px" — 38→62.
            // JEDENASTA runda: mapa oddała sobie wysokość z powrotem, w
            // dwóch krokach do pełnych 610 (patrz `mapSectionHeight`) —
            // 62→42→30, dokładnie tyle ile było w tamtej potwierdzonej
            // wersji sprzed serii zmniejszeń.
            // DWUNASTA runda: user (mimo potwierdzenia w kodzie że mapa ma
            // już 610) dalej zgłasza odsłoniętą przestrzeń — cały blok
            // (statystyki→znaczki→tekst) przesunięty niżej jako całość,
            // odstępy MIĘDZY nimi (28/34) zostają bez zmian, zgodnie z
            // wyraźną prośbą "zachowując te same odstępy" — 30→52.
            statsPlaque
                .padding(.horizontal, 40)
                .padding(.top, 52)
            // 12.09.2026, druga runda: "dolna część trochę przeładowana...
            // można minimalnie zwiększyć odstępy między statystykami a
            // pieczątkami" — 30→38. SZÓSTA runda: 38→55 (za dużo).
            // SIÓDMA runda: "znaczki wyżej, bezpośrednio pod statystykami"
            // — 55→28.
            stampsRow
                .padding(.top, 28)
            // SZÓSTA runda: "tekst pod znaczkami za blisko dekoracji" —
            // 26→42. SIÓDMA runda: "zbyt dużo pustej przestrzeni po
            // tekście" — 42→26 (powrót, plus patrz `footer` — sam tekst
            // teraz większy/wyraźniejszy zamiast dodatkowego odstępu).
            // ÓSMA runda: "przesunąć blok tekstowy 15-25px niżej" — 26→48.
            // JEDENASTA runda: weryfikacja spójności rytmu po powrocie
            // mapy do 610 — mapa→statystyki=30, statystyki→znaczki=28, ale
            // znaczki→tekst zostały na 48 (dostrajane jeszcze przy mapie
            // 480pt) — wyraźny skok względem pozostałych dwóch. 48→34,
            // bliżej reszty łańcucha.
            footer
                .padding(.top, 34)
            // SZÓSTA runda: canvas ma teraz STAŁĄ wysokość wynikającą z
            // proporcji pliku tła (patrz `renderPosterImage`), nie z
            // treści — user zgłosił że to zostawiało duży, pusty fragment
            // tła POD stopką zamiast dokleić ją do samej krawędzi. Elastyczny
            // `Spacer` sprawia, że VStack faktycznie WYKORZYSTUJE nadwyżkę
            // wysokości zaproponowaną przez zewnętrzny `.frame()` zamiast
            // renderować się na swojej minimalnej, naturalnej wysokości i
            // zostawiać resztę jako martwe tło — stopka zawsze ląduje na
            // samym dole, niezależnie ile dokładnie treści ma dany user.
            // SIÓDMA runda: skrócona mapa + ściaśnięte odstępy same w sobie
            // znacznie zmniejszają nadwyżkę, którą ten Spacer musi
            // pochłonąć — mniejszy `minLength` (nie zero: user chce stopkę
            // NA dole, nie w połowie, więc jakiś oddech przed nią zostaje).
            Spacer(minLength: 10)
            brandBanner
                .padding(.top, 30)
        }
        .padding(44)
        .background(paperBackground)
    }

    /// Ciemny pasek na samej krawędzi plakatu (07.09.2026, user przesłał
    /// referencyjny mockup z takim zamknięciem kompozycji) — ujemny
    /// padding znosi zewnętrzny margines `.padding(44)` z lewej/prawej/
    /// dołu TYLKO dla tego elementu, żeby sięgał do samych krawędzi
    /// canvasu, tak jak we wzorcu.
    private var brandBanner: some View {
        Text(L("Created with PMemories").uppercased())
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .tracking(2)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(red: 0.13, green: 0.12, blue: 0.16))
            .padding(.horizontal, -44)
            .padding(.bottom, -44)
    }

    /// Prawdziwa, fotorealistyczna tekstura papieru (06.09.2026, user
    /// dostarczył zestaw wygenerowanych teksturek — "teraz masz wszystko",
    /// losowana z `paperTextureNames`) zamiast programowo generowanego
    /// ziarna. Podpięta przez `.background(paperBackground)` na VStacku
    /// (NIE osobny `GeometryReader`/`ZStack` — połączenie `GeometryReader`
    /// z `.fixedSize()` użytym do zmierzenia dynamicznej wysokości
    /// zapętlało layout do zera, obserwowane na urządzeniu jako
    /// całkowicie pusty ekran). `.background()` automatycznie dopasowuje
    /// rozmiar obrazka do już wyliczonego rozmiaru VStacka — bez żadnej
    /// ręcznej geometrii.
    private var paperBackground: some View {
        Image(backgroundTextureName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipped()
    }

    /// 11.09.2026, user: "co z nasza dekoracja... trzeba to umiescic zeby
    /// wygladalo inaczej" — po trzech nieudanych próbach wciskania
    /// dodatków W GĘSTĄ mapę (zawsze kolidowały albo wyglądały bez sensu)
    /// nowa, inna strefa: puste marginesy PO BOKACH nagłówka (`header` ma
    /// stałą wysokość, tytuł wyśrodkowany, więc przy pełnej szerokości
    /// 1080pt zostaje sporo pustego miejsca po lewej/prawej) — jedyne
    /// miejsce na plakacie, które NIE jest już gęsto wypełnione treścią.
    private var header: some View {
        ZStack {
            Image("PosterDecoLeafSpray")
                .resizable().scaledToFit().frame(width: 70)
                .rotationEffect(.degrees(-15))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .offset(x: -430, y: 130)
            Image("PosterDecoRopeBow")
                .resizable().scaledToFit().frame(width: 60)
                .rotationEffect(.degrees(8))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                .offset(x: 440, y: 125)
            headerContent
        }
    }

    private var headerContent: some View {
        // 13.09.2026, siódma runda: "tytuł zbyt blisko elementów tła...
        // logo powinno mieć trochę więcej przestrzeni od tytułu" —
        // 12→20 między logo a tytułem/podtytułem.
        VStack(spacing: 20) {
            // 13.09.2026, TYMCZASOWO na czas testu nowych teł scrapbookowych:
            // prawie wszystkie mają WYPALONĄ w grafice własną "kartę
            // tytułową" (Adventure Awaits/Explore the World/itp.) dokładnie
            // w lewym górnym rogu, gdzie wcześniej siedziało `originStamp` —
            // i osobno często ten sam napis "Collect Moments Not Things" co
            // nasze `adventureAwaitsStamp` w prawym rogu. Zamiast kolidować
            // z ich grafiką w rogach: logo wyśrodkowane, `adventureAwaitsStamp`
            // wyłączone (duplikowałoby tekst z tła). Jedyne miejsce wspólne
            // dla WSZYSTKICH wariantów teła — środek góry, tam gdzie i tak
            // ląduje tytuł "My Travel Journey" poniżej.
            HStack {
                Spacer()
                originStamp
                Spacer()
            }
            .padding(.top, 8)
            // 09.09.2026, user: "w napisie nie mamy zadnych kolorow" —
            // referencja koloruje konkretne SŁOWA ("My" na czerwono), ale
            // tytuł idzie przez `L(...)` (27 języków) — dzielenie po
            // angielskich słowach zepsułoby to w każdym innym języku.
            // Zamiast tego: cały tytuł w cieplejszym, bogatszym kolorze
            // (zamiast płaskiego brązu) + prawdziwy samolocik z przerywaną
            // smugą przelatujący obok, tak jak we wzorcu — dodaje kolor/
            // charakter bez zakładania szyku wyrazów w innym języku.
            ZStack(alignment: .topTrailing) {
                Text(L("My Travel Journey"))
                    .font(.system(size: 58, weight: .heavy, design: .serif))
                    .foregroundStyle(Color(red: 0.55, green: 0.16, blue: 0.12))
                titleFlourish
                    .offset(x: 36, y: -6)
            }
            Text(L("A collection of memories around the world").uppercased())
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.24))
            decorativeDivider
        }
    }

    /// Prawdziwy, wycięty kompas zamiast SF Symbol (06.09.2026, user
    /// dostarczył zestaw zdjęć — wycięty ręcznie z jednego z nich,
    /// zachowując oryginalną przezroczystość).
    /// 13.09.2026, czternasta runda — PRAWDZIWA przyczyna "uciętego
    /// kompasu": to NIE był bug layoutu (padding/rotacja/mapa) — sam plik
    /// `TravelJourneyCompass.png` ma niesymetrycznie wycięty prawy bok
    /// obudowy (widoczne po powiększeniu zrzutu usera: lewa strona pełna,
    /// okrągła z "W", prawa ścięta tuż przy "E"). Żadna poprawka
    /// odstępu/pozycji nie mogła tego naprawić, bo wada jest wypalona w
    /// samym obrazku. Zamiennik: `PosterDecoCompass` — ten sam motyw,
    /// pełny i symetryczny, już w projekcie, dotąd nieużywany nigdzie.
    private var decorativeDivider: some View {
        HStack(spacing: 10) {
            flourishLine
            Image("PosterDecoCompass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(-8))
            flourishLine.scaleEffect(x: -1)
        }
        .foregroundStyle(Color(red: 0.45, green: 0.38, blue: 0.28).opacity(0.6))
        .padding(.top, 4)
    }

    /// Samolocik z przerywaną smugą przy tytule (09.09.2026, referencyjny
    /// mockup) — czysto dekoracyjny akcent, nie prawdziwa trasa (ta jest na
    /// mapie, `flightPathOverlay`).
    private var titleFlourish: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 30))
                path.addQuadCurve(to: CGPoint(x: 70, y: 0), control: CGPoint(x: 40, y: 34))
            }
            .stroke(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            Image(systemName: "airplane")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.7))
                .rotationEffect(.degrees(35))
                .position(x: 70, y: 0)
        }
        .frame(width: 90, height: 40)
    }

    private var flourishLine: some View {
        HStack(spacing: 3) {
            Circle().frame(width: 3, height: 3)
            Rectangle().frame(width: 90, height: 1.5)
        }
    }

    /// Powiększone (05.09.2026, user: "apple maps jest bardziej widoczne
    /// niz logo apki") — Apple wymaga widocznej plakietki "Apple Maps" na
    /// snapshotcie mapy (nie można jej usunąć/zmniejszyć), więc jedyny
    /// sposób na zbalansowanie to własne logo WYRAŹNIE większe i mocniejsze
    /// niż wcześniej (16pt ikona + wypełnione tło zamiast cienkiej
    /// przerywanej obwódki).
    /// Prawdziwe logo appki zamiast generycznej ikonki aparatu (09.09.2026,
    /// user: "nasze logo musi widniec na gorze" — ten sam kolorowy znak
    /// `AppLogoMark` co ikona appki/onboarding, nie osobna, nowa grafika).
    /// Tło/obwódka w delikatnym gradiencie ECHUJĄCYM kolory samego logo
    /// (niebiesko-fioletowy) zamiast płaskiego białego kółka — user: "w
    /// napisie nie mamy zadnych kolorow... mozna pomyslec o bardziej
    /// ciekawszym rozwiazaniu a nie tylko na bialym kolku".
    /// 11.09.2026, user: "poprawiamy nasze logo w lewym gornym rogu bo
    /// wyglada gorzej niz zle" — przyczyna: `AppLogoMark` to prawdziwa
    /// ikonka appki, czyli NIEPRZEZROCZYSTY zaokrąglony kwadrat z WŁASNYM
    /// białym tłem wypalonym w pikselach (tak działają ikonki iOS). Owinięcie
    /// go w DODATKOWE kółko z własnym gradientem/obwódką dawało podwójne
    /// tło — biały kwadrat ikonki widoczny wewnątrz kółka, plus przy 34pt
    /// detal (P/M/słońce/mewa) zlewał się w nieczytelną plamę. Fix: bez
    /// opakowania w kółko w ogóle — sama ikonka, większa (czytelna), z
    /// cieniem zamiast sztucznego tła.
    /// 11.09.2026, user pokazał referencyjny wordmark: "PM" w tym samym
    /// niebiesko-fioletowym gradiencie co logo, "emories" zwykłym ciemnym
    /// kolorem, zwykła wielkość liter (nie WERSALIKI). `Text` + `Text`
    /// (konkatenacja) zamiast jednego stylu na cały string — każdy
    /// segment niesie WŁASNY `.foregroundStyle`/`.font`.
    private var originStamp: some View {
        VStack(spacing: 6) {
            Image("AppLogoMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
            (
                Text("PM")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.29, green: 0.36, blue: 0.86), Color(red: 0.58, green: 0.4, blue: 0.86)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                + Text("emories")
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.11))
            )
            .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .rotationEffect(.degrees(-6))
    }

    /// 13.09.2026, TYMCZASOWO nieużywane — patrz `headerContent`, na czas
    /// testu nowych teł scrapbookowych duplikowałoby ich własny napis.
    /// Zostawione zdefiniowane (nie usunięte), żeby łatwo wrócić przy
    /// starych teksturkach papieru.
    private var adventureAwaitsStamp: some View {
        VStack(spacing: 2) {
            Text(L("Adventure Awaits").uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(L("Collect Moments").uppercased())
                .font(.system(size: 9, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.2, green: 0.35, blue: 0.25))
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).opacity(0.6))
        .rotationEffect(.degrees(6))
    }

    @ViewBuilder
    private var mapSection: some View {
        ZStack {
            // 13.09.2026, dziewiąta runda: karta mapy ma WŁASNE `.clipped()`
            // (patrz koniec `mapCard`), zdjęcia są OSOBNĄ warstwą w tym
            // samym ZStacku żeby dalej mogły celowo wychodzić poza jej
            // dolną krawędź — gdyby `.clipped()` siedziało na całym
            // `mapSection` (obejmując też zdjęcia), obcinałoby też ten
            // zamierzony efekt.
            mapCard
            // Polaroidy świadomie wychodzą POZA dolną krawędź mapy (06.09.2026,
            // user: "zdjęcia mają nachodzić na mapę, nie siedzieć w
            // zamkniętej sekcji") — `.offset()` nie wpływa na wysokość
            // liczoną przez layout, więc zdjęcia mogą wizualnie
            // "wchodzić" na kartę statystyk poniżej bez żadnej sztuczki z
            // clipowaniem.
            ForEach(polaroids) { polaroid in
                PolaroidView(polaroid: polaroid)
                    .offset(x: polaroid.offsetX, y: polaroid.offsetY)
                    .rotationEffect(.degrees(polaroid.rotation))
            }
        }
        .frame(height: Self.mapSectionHeight)
    }

    /// Sama karta mapy (obraz + podświetlenia krajów + trasy + piny +
    /// ramka + cień), WYDZIELONA z `mapSection` (13.09.2026, dziewiąta
    /// runda) — żeby mogła mieć WŁASNE, twarde `.clipped()` bez obcinania
    /// zdjęć, które celowo wychodzą poza jej krawędź. Patrz stała
    /// `mapSectionHeight` po wyjaśnienie PRAWDZIWEJ przyczyny buga (obraz
    /// w trybie `.fill` rósł ponad zadeklarowaną wysokość i malował się na
    /// statystykach).
    @ViewBuilder
    private var mapCard: some View {
        ZStack {
            if let mapSnapshot {
                Image(uiImage: mapSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // 13.09.2026, punkt 1 z nowej listy: "mapa wygląda jak
                    // zrzut ekranu z Maps, nie jak część starego atlasu...
                    // zmniejsz intensywność kolorów" — przygaszona nasycona
                    // (tylko surowa mapa Apple, NIE nasze kolorowe
                    // podświetlenia krajów/piny poniżej — te zostają pełne)
                    // + ciepła sepiowa poświata ujednolicająca z papierem.
                    .saturation(0.55)
                    .overlay(Color(red: 0.55, green: 0.4, blue: 0.22).opacity(0.1))
                    .overlay(countryFillsOverlay)
                    .overlay(flightPathOverlay)
                    .overlay(
                        // 12.09.2026, druga runda: "piny są dość duże i
                        // białe... delikatniejszy cień" — pomniejszone
                        // (22→16) i subtelniejszy cień.
                        // 12.09.2026, feedback narzeczonej (nocna mapa):
                        // czerwono-białe piny gubiły się na wymuszonej teraz
                        // ciemnej mapie — kremowo-złote (ten sam odcień co
                        // podświetlone kraje, więc piny czytają się jako
                        // "część tej samej rodziny kolorów", nie osobny
                        // element) z ciemną kropką w środku dla kontrastu.
                        // 12.09.2026, trzecia runda: "piny na Bliskim
                        // Wschodzie mało widoczne przy pomniejszeniu —
                        // jaśniejszy obrys, trochę większa tarcza, delikatny
                        // cień" — 16→18, jaśniejszy kremowy, dodana cienka
                        // kremowa obwódka (halo) dla kontrastu na KAŻDYM tle
                        // mapy (nie tylko ciemnym oceanie), mocniejszy cień.
                        // 13.09.2026, piąta runda: "znaczniki wyglądają jak
                        // element techniczny... mały vintage pin, subtelna
                        // złota obwódka, delikatny cień, bez efektu aplikacji
                        // mapowej" — mniejsze (18→16), kremowo-złota tarcza,
                        // obwódka zmieniona z jasnokremowej na cieplejszą,
                        // stonowaną złotą, cień zamieniony z "poświaty" na
                        // prawdziwy rzucony cień (przesunięcie w dół zamiast
                        // samego rozmycia).
                        // 13.09.2026: dzień/noc — na jasnej mapie klasyczny
                        // czerwono-biały pin (dobry kontrast na jasnym
                        // lądzie, ten sam duch co oryginalny mockup sprzed
                        // trybu nocnego); na ciemnej zostaje kremowo-złoty.
                        ForEach(Array(mapPinPoints.enumerated()), id: \.offset) { _, point in
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    isDaytimeMap ? Color(red: 0.75, green: 0.16, blue: 0.12) : Color(red: 0.94, green: 0.85, blue: 0.6),
                                    isDaytimeMap ? .white : Color(red: 0.16, green: 0.14, blue: 0.11)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            (isDaytimeMap ? Color.white : Color(red: 0.82, green: 0.66, blue: 0.32)).opacity(0.85),
                                            lineWidth: 1.1
                                        )
                                        .scaleEffect(1.15)
                                )
                                .shadow(color: .black.opacity(isDaytimeMap ? 0.3 : 0.4), radius: 1.5, y: 1)
                                .position(point)
                        }
                    )
                    // 13.09.2026, piętnasta runda: user — "ładnie zaokrąglone
                    // rogi mapy zniknęły, po bokach jest obwódka ale góra/dół
                    // nie mają jej wcale". Realna przyczyna: `.clipShape`
                    // (zaokrąglone rogi) i obwódki BYŁY rysowane na obrazie
                    // W JEGO WŁASNYM, RAW rozmiarze z `.aspectRatio(.fill)`
                    // (który — patrz `mapSectionHeight` — bywa WYŻSZY niż
                    // zadeklarowane `mapSectionHeight`), a dopiero POTEM
                    // (niżej, `.frame(height:).clipped()` na całym ZStacku)
                    // całość była obcinana zwykłym PROSTOKĄTEM — więc górna/
                    // dolna zaokrąglona krawędź razem z fragmentem obwódki
                    // po prostu znikała pod cięciem, zostawiając płaskie,
                    // "gołe" krawędzie. Fix: przytnij do właściwej wysokości
                    // NAJPIERW, dopiero na TYM (już poprawnym) rozmiarze
                    // rysuj zaokrąglenie/obwódkę/cień — więc obie krawędzie
                    // (góra/dół) dostają dokładnie to samo co lewa/prawa.
                    .frame(height: Self.mapSectionHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(red: 0.93, green: 0.86, blue: 0.7), lineWidth: 3))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 9)
            } else {
                RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.4))
            }
        }
        // 13.09.2026, dziewiąta runda: user (po dodatkowej konsultacji) —
        // "nie generować mapy w innych proporcjach, to może pogorszyć
        // jakość". Zgoda — zamiast zmieniać `options.size` w
        // `renderMapSnapshot`, ograniczam WYŁĄCZNIE warstwę wyświetlania:
        // konkretna wysokość + `.clipped()` na tym DEDYKOWANYM kontenerze
        // karty mapy (nie na całej `mapSection`, żeby nie obcinać zdjęć
        // celowo wychodzących poza jej krawędź — patrz `mapSection`). To
        // jest to źródłowe miejsce, gdzie obraz w trybie `.fill` mógł
        // wcześniej urosnąć ponad zadeklarowaną wysokość i namalować się
        // na statystykach.
        // DZIESIĄTA runda: dodane wcześniej `.frame(maxWidth: .infinity)`
        // PRZED `.frame(height:)` to DWA OSOBNE wywołania `.frame()` w
        // łańcuchu — każde jest osobnym kontenerem layoutu, a SwiftUI
        // liczy je SEKWENCYJNIE (drugie dostaje jako wejście WYNIK
        // pierwszego, nie oryginalną propozycję od rodzica) — to
        // faktycznie ZWĘZIŁO mapę (user: "mapę tylko zwęził, odsłonił
        // fragment tła"). Usunięte — szerokość wraca do NIEJAWNEJ,
        // odziedziczonej po rodzicu (dokładnie jak działało przed tym
        // fixem), tylko wysokość jest teraz jawnie ograniczona.
        .frame(height: Self.mapSectionHeight)
        .clipped()
    }

    /// Podświetlone odwiedzone kraje — narysowane PIERWSZE (pod trasami i
    /// pinezkami), żeby te wciąż wyraźnie odcinały się na wierzchu
    /// (12.09.2026, Warstwa 1 feedbacku narzeczonej). Każdy kraj to osobny
    /// `Path` z regułą `evenOdd`, żeby dziury (np. enklawy) faktycznie
    /// wycinały się z wypełnienia zamiast się z nim zlewać.
    @ViewBuilder
    private var countryFillsOverlay: some View {
        ForEach(countryFills) { country in
            let outline = countryPath(country)
            // TRZYDZIESTA PIERWSZA runda (wycofana): rozmyta "poświata"
            // (`.blur`) pod spodem — user: poprzednia, prostsza wersja
            // (samo wypełnienie + ostry obrys) była wyraźnie lepsza,
            // rozmycie wyglądało niechlujnie, nie elegancko. Wraca prosty
            // dwuwarstwowy układ; mocniejszy kontrast realizowany samym
            // kolorem/kryciem (patrz `renderMapSnapshot`), nie efektem
            // rozmycia.
            outline.fill(country.fill, style: FillStyle(eoFill: true))
            outline.stroke(country.stroke, lineWidth: 1.2)
        }
    }

    private func countryPath(_ country: CountryFillShape) -> Path {
        Path { path in
            for polygon in country.polygons {
                for ring in polygon {
                    guard let first = ring.first else { continue }
                    path.move(to: first)
                    for point in ring.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.closeSubpath()
                }
            }
        }
    }

    /// Przerywana trasa łącząca odwiedzone miejsca + samolociki wzdłuż
    /// drogi (07.09.2026, user przesłał referencyjny mockup z dokładnie
    /// takim elementem). 11.09.2026: rysowana teraz OSOBNO per podróż
    /// (`mapRoutePaths`, patrz `renderMapSnapshot`) — user: "czy mapa moze
    /// pokazywac rzeczywista siec podrozy". Każda pod-trasa to jedna
    /// prawdziwa podróż w rzeczywistej kolejności zwiedzania; POMIĘDZY
    /// podróżami nigdy nie ma linii, żeby mapa nie sugerowała lotu, który
    /// nigdy się nie odbył.
    @ViewBuilder
    private var flightPathOverlay: some View {
        ForEach(Array(mapRoutePaths.enumerated()), id: \.offset) { _, route in
            if route.count > 1 {
                Path { path in
                    path.move(to: route[0])
                    for point in route.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                // 12.09.2026, druga runda: "cieńsze, bardziej delikatne
                // linie... mniejsze symbole samolotów... mapa powinna być
                // tłem, nie głównym wykresem lotów" — cieńsza linia
                // (2.5→1.5), niższa opacity, mniejszy samolot (16→11).
                // TRZECIA runda (nocna mapa): atramentowa linia znikała na
                // ciemnym tle — zamieniona na jasnoszaro-złotą.
                // CZWARTA runda: "trasy bardziej subtelne, cienkie i
                // eleganckie" — 1.5→1.1, niższa opacity, drobniejszy dash.
                // PIĄTA runda: poszliśmy za daleko — "linia jest teraz
                // dość subtelna, powinna być trochę jaśniejsza i minimalnie
                // grubsza, bardziej widoczna na ciemnym tle, ale bez
                // dominowania nad zdjęciami" — 1.1→1.3, opacity 0.42→0.6,
                // jaśniejszy odcień.
                // 13.09.2026: dzień/noc — na jasnej mapie wraca ciemny
                // atramentowy odcień (ten jasnoszaro-złoty ZNIKAŁBY na
                // jasnym tle, dokładnie ten sam problem odwrotnie).
                .stroke(
                    isDaytimeMap
                        ? Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.4)
                        : Color(red: 0.87, green: 0.82, blue: 0.68).opacity(0.6),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [5, 4])
                )
                // 12.09.2026, zgłoszony bug (zrzut usera): trasa z kilkoma
                // bliskimi przystankami (city-hopping) miała samolocik NA
                // KAŻDYM odcinku — kilka nałożonych, różnie obróconych ikon
                // blisko siebie zlewało się w czarną "gwiazdkę". Teraz
                // JEDEN samolocik na całą linię, na jej środku wg realnej
                // długości trasy (nie środku listy punktów), z kątem
                // odcinka w którym faktycznie leży.
                if let midpoint = routeMidpoint(route) {
                    Image(systemName: "airplane")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            (isDaytimeMap ? Color(red: 0.16, green: 0.14, blue: 0.11) : Color(red: 0.9, green: 0.85, blue: 0.7))
                                .opacity(isDaytimeMap ? 0.6 : 0.75)
                        )
                        .rotationEffect(.degrees(midpoint.angle + 45))
                        .position(midpoint.point)
                }
            }
        }
    }

    /// Punkt w połowie CAŁKOWITEJ długości trasy (nie połowie listy
    /// punktów — dla tras z nierównymi odcinkami to nie to samo) + kąt
    /// odcinka, w którym ten punkt faktycznie leży, do obrotu ikony
    /// samolotu. Patrz `flightPathOverlay`.
    private func routeMidpoint(_ route: [CGPoint]) -> (point: CGPoint, angle: Double)? {
        guard route.count > 1 else { return nil }
        let segments = zip(route, route.dropFirst()).map { a, b in (a, b, Double(hypot(b.x - a.x, b.y - a.y))) }
        let totalLength = segments.reduce(0) { $0 + $1.2 }
        guard totalLength > 0 else {
            return (route[0], 0)
        }
        var remaining = totalLength / 2
        for (a, b, length) in segments {
            if remaining <= length || length == 0 {
                let t = length > 0 ? CGFloat(remaining / length) : 0
                let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let angle = Double(atan2(b.y - a.y, b.x - a.x) * 180 / .pi)
                return (point, angle)
            }
            remaining -= length
        }
        let (a, b, _) = segments.last!
        return (route.last!, Double(atan2(b.y - a.y, b.x - a.x) * 180 / .pi))
    }

    /// Prosta, czysta ramka zamiast paska dashboardu (07.09.2026, user
    /// przesłał referencyjny mockup — cienka obwódka na tle samego
    /// papieru, bez osobnej karty/cienia/obrotu, cienkie proste linie
    /// zamiast kropkowanej perforacji, dokładnie jak we wzorcu).
    private var statsPlaque: some View {
        HStack(spacing: 0) {
            statColumn(icon: "globe", value: "\(stats.countryCount)", label: L("Countries"))
            plainDivider
            statColumn(icon: "signpost.right.fill", value: "\(stats.tripCount)", label: L("Trips"))
            plainDivider
            statColumn(icon: "mappin.and.ellipse", value: stats.totalKm.formatted(), label: L("KM Travelled"))
            plainDivider
            statColumn(icon: "airplane", value: "\(stats.flightCount)", label: L("Flights"))
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        // 13.09.2026, piąta runda: "pierwsza statystyka trochę zasłonięta
        // przez dekoracyjne elementy tła... delikatna, półprzezroczysta
        // jasna warstwa pod spodem" — nowe scrapbookowe tła są dużo
        // gęstsze/bardziej ilustrowane niż stare czyste teksturki papieru,
        // więc sam tekst nie zawsze wystarcza. Subtelna kremowa podkładka
        // POD istniejącą cienką obwódką (ta sama forma, nie nowa "karta"),
        // żeby liczby czytały się niezależnie od tego co akurat jest pod
        // spodem.
        // SZESNASTA runda: "kompas w tle wchodzi pod panel, traci
        // czytelność" — zasada ogólna (nie tylko ten jeden kompas): panel
        // statystyk musi być czytelny NIEZALEŻNIE które z 11 teł/która
        // dekoracja akurat pod nim wypadnie — 0.55→0.75, wyraźnie mocniejsze
        // krycie zamiast dostrajania pod jeden konkretny przypadek.
        // DWUDZIESTA runda: user złapał na zrzucie że TA SAMA sztuczka na
        // stopce (0.5) dalej przepuszczała ciemne, odręczne pismo tła —
        // podniesione tam do 0.85, dla spójności panel statystyk też
        // 0.75→0.85 (ten sam poziom pewności w całym plakacie).
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.98, green: 0.95, blue: 0.87).opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.45), lineWidth: 1.5))
    }

    private var plainDivider: some View {
        Rectangle()
            .fill(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.3))
            .frame(width: 1.2, height: 44)
    }

    private func statColumn(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20))
            // 12.09.2026, trzecia runda: "statystyki mogłyby mieć trochę
            // większy kontrast... liczby odrobinę ciemniejsze" — bez nowego
            // tła/karty (user: "nie dodawałbym nowych ramek ani
            // ozdobników"), sama liczba po prostu ciemniejsza/mocniejsza
            // niż reszta plakietki.
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.05))
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
        }
        .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.11))
        .frame(maxWidth: .infinity)
    }

    /// Małe, płaskie znaczki krajów zamiast dużych kart z tłem/cieniem
    /// (09.09.2026, user przesłał referencyjny mockup — gęsto upakowany,
    /// jednorzędowy pas prawdziwych ilustrowanych naklejek z kolorową
    /// obwódką, bez żadnego tła/cienia/karty, zupełnie inna rodzina
    /// wizualna niż poprzednie duże "przyciski"). `journeyStampAssetByCountryCode`
    /// — 215 wyciętych znaczków w DOKŁADNIE tym stylu (`JourneyStampAssets.swift`)
    /// — MA WŁASNĄ obwódkę/ilustrację wypaloną w pikselach, więc te znaczki
    /// idą na canvas BEZ żadnej dodatkowej ramki. Stary `worldStickerAssetByCountryCode`
    /// (Travel Passport, inny styl — biała naklejka bez obwódki) i flaga
    /// emoji zostają jako fallback TYLKO dla krajów spoza nowego zestawu
    /// (drobne terytoria, nigdy nie było ich na wyciętych arkuszach) — tam
    /// nasza własna cienka obwódka nadal ma sens, bo assety jej nie mają.
    /// 12.09.2026, feedback narzeczonej (przez usera): "nie powinniśmy mieć
    /// stałego miejsca na pieczątki... 47 countries → 47 stamps i mamy
    /// katastrofę". Zamiast pokazywać WSZYSTKIE kraje, tnie do
    /// `displayedCountryStamps` (wybrane przez `TravelRarityScore` —
    /// najrzadsze/najdalsze, nie pierwsze z brzegu) i dokleja kafelek
    /// "+N MORE" gdy coś zostało odcięte, tego samego rozmiaru co reszta.
    private var stampsRow: some View {
        let slotCount = displayedCountryStamps.count + (hiddenStampCount > 0 ? 1 : 0)
        // 13.09.2026, siedemnasta runda: "pieczątki trochę za małe, szczególnie
        // napisy... powiększyć o 15-20%, ale zostać przy JEDNYM rzędzie —
        // nie dwa rzędy przy 14 krajach". `visibleStampCount` już z góry
        // ogranicza liczbę pieczątek do max 12 (+"+N MORE") niezależnie ile
        // krajów ma user — rząd WIĘC NIGDY nie musi się zawijać, nie trzeba
        // dodawać osobnej logiki auto-wrap. Odstęp między kolumnami ściaśnięty
        // (8→5), żeby powiększone pieczątki dalej mieściły się w jednym rzędzie.
        // OSIEMNASTA runda: jeszcze raz nieco większe pieczątki (+10-15%) —
        // odstęp ściaśniony dalej (5→3), żeby dalej mieściły się w jednym rzędzie.
        // DZIEWIĘTNASTA runda: user — "nie zmniejszamy pieczątek, rozmiar
        // OK, tylko trochę więcej odstępu (+2)" — 3→5.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: min(max(slotCount, 1), 20))
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(displayedCountryStamps.enumerated()), id: \.element.code) { index, stamp in
                stampCard(stamp: stamp, index: index)
            }
            if hiddenStampCount > 0 {
                moreStampsCard(count: hiddenStampCount)
            }
        }
        // 13.09.2026, ósma runda: "pierwszy znaczek zaczyna się bardzo
        // blisko lewej krawędzi, ostatni i +2 MORE blisko prawej" — rząd
        // nie miał żadnego marginesu poziomego, sięgał do samej krawędzi
        // treści (44pt zewnętrznego paddingu plakatu). Dodany wewnętrzny
        // margines, taki sam kierunek co `statsPlaque` (40pt) tylko nieco
        // węższy, żeby więcej znaczków zmieściło się w rzędzie.
        // SIEDEMNASTA runda: 20→16, odzyskuje trochę szerokości pod
        // powiększone pieczątki, margines wciąż realny (nie do samej krawędzi).
        // OSIEMNASTA runda: "jeszcze delikatnie, 10-15% więcej, jeden rząd
        // zostaje" — 16→12, odzyskuje jeszcze trochę szerokości.
        // DWUDZIESTA TRZECIA runda: "okrągły stempel 'TRAVEL...SEE MORE' z
        // tła koliduje z pierwszymi znaczkami" — ten stempel jest WYPALONY
        // w grafice tła (nie da się go przesunąć/przyciemnić z kodu), więc
        // zamiast tego lekko asymetryczny margines — więcej z lewej (gdzie
        // ten stempel siedzi), tyle samo z prawej co wcześniej.
        .padding(.leading, 24)
        .padding(.trailing, 12)
    }

    /// Kafelek "+N MORE" — user (feedback narzeczonej): "COUNTRY PASSPORT...
    /// + 32 MORE... to jest wręcz lepsze projektowo... dużo podróżujesz →
    /// poster nie robi się coraz bardziej zaśmiecony". Ten sam gabaryt co
    /// `stampCard`, żeby pasował w tym samym rzędzie siatki.
    private func moreStampsCard(count: Int) -> some View {
        VStack(spacing: 2) {
            Text("+\(count)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            // DWUDZIESTA TRZECIA runda: "'+2 MORE' trochę ciężkie wizualnie
            // vs znaczki obok — zmniejszyć grubość/rozmiar napisu MORE" —
            // 11→9, bold→semibold.
            Text(L("MORE"))
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.75))
        .frame(maxWidth: .infinity)
        // 13.09.2026, siedemnasta runda: "pieczątki za małe... powiększyć o
        // 15-20%, jeden rząd zostaje" — 64→74 (~15.6%), ten sam gabaryt co
        // `stampCard` (muszą się zgadzać, ta karta idzie w tej samej siatce).
        // OSIEMNASTA runda: "jeszcze delikatnie, 10-15% więcej" — 74→85.
        .frame(height: 85)
        // DZIEWIĘTNASTA runda: "+2 MORE wygląda jak kolejna pieczątka
        // przyklejona do ostatniej — odsunąć w prawo" — dodatkowy margines
        // od lewej WEWNĄTRZ własnej kolumny siatki, żeby wizualnie odkleić
        // się od poprzedniego znaczka bez zmiany szerokości kolumny innych.
        // DWUDZIESTA PIERWSZA runda: "dalej trochę za blisko" — 8→16.
        .padding(.leading, 16)
        // DWUDZIESTA DRUGA runda: user pokazał zrzut — na jednym z teł ta
        // karta siedziała na gęstej, mapopodobnej ilustracji w tle, a
        // przerywana ramka BEZ ŻADNEGO wypełnienia pozwalała tej dekoracji
        // przebijać się przez cały środek, więc "+2 MORE" wyglądało jak
        // fragment tła, nie jak element rzędu pieczątek (który obok ma
        // solidne, kolorowe znaczki-ilustracje). Fix: własna jasna
        // plakietka pod ramką — ten sam poziom krycia co reszta plakatu
        // (0.85), więc karta zawsze czyta się jako spójny element UI,
        // niezależnie co akurat jest narysowane pod spodem.
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 0.98, green: 0.95, blue: 0.87).opacity(0.85)))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(red: 0.16, green: 0.14, blue: 0.11).opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        )
    }

    @ViewBuilder
    private func stampCard(stamp: CountryStamp, index: Int) -> some View {
        if let assetName = journeyStampAssetByCountryCode[stamp.code] {
            // 13.09.2026, siedemnasta runda: "pieczątki, szczególnie napisy
            // na nich, trochę za małe" — napisy są wypalone W SAMEJ grafice
            // znaczka, więc powiększenie całej karty (64→74, ~15.6%)
            // powiększa też tekst proporcjonalnie, bez osobnego strojenia
            // fontu.
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                // OSIEMNASTA runda: "jeszcze delikatnie, 10-15% więcej" — 74→85.
                .frame(height: 85)
        } else {
            VStack(spacing: 4) {
                if let oldAsset = worldStickerAssetByCountryCode[stamp.code] {
                    Image(oldAsset).resizable().aspectRatio(contentMode: .fit).frame(height: 52)
                } else {
                    Text(stamp.flag).font(.system(size: 34))
                }
                Text(stamp.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Self.stampColor(index))
            .frame(maxWidth: .infinity)
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Self.stampColor(index), lineWidth: 1.5))
        }
    }

    private static func stampColor(_ index: Int) -> Color {
        let palette: [Color] = [.red, .green, .blue, .orange, .purple, .teal, .brown, .pink]
        return palette[index % palette.count].opacity(0.75)
    }

    private var footer: some View {
        // 13.09.2026, siódma runda: "'14 Countries • Countless Memories'
        // większe i czytelniejsze, wyraźna hierarchia ze sloganem pod
        // spodem, belka może zostać ale subtelniejsza i krótsza" — główny
        // tekst 17→21 (heavy zamiast bold — wyraźnie WAŻNIEJSZY niż
        // slogan), slogan lekko mniejszy (13→12). Belka: była
        // `.frame(maxWidth: .infinity)` (pełna szerokość plakatu) — teraz
        // przylega tylko do treści (`fixedSize`), sama karta węższa i
        // bardziej przezroczysta (0.5→0.35), całość wyśrodkowana osobnym
        // kontenerem na pełną szerokość.
        VStack(spacing: 8) {
            flourishLine.frame(width: 140)
            Text("\(stats.countryCount) \(L("Countries")) • \(L("Countless Memories"))")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
            Text(L("Every place has a story. Every memory lasts forever."))
                .font(.system(size: 12, weight: .medium, design: .serif))
                .italic()
        }
        .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.11))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 13.09.2026, szósta runda: "nie może nachodzić na napis 'Good
        // People Good Places' ani elementy tła" — ten napis jest WYPALONY w
        // grafice nowych teł scrapbookowych, więc nie da się go po prostu
        // przesunąć; zamiast tego własny tekst dostaje subtelną kremową
        // podkładkę (ta sama sztuczka co `statsPlaque`), żeby zawsze był
        // czytelny niezależnie co akurat jest pod spodem.
        // SZESNASTA runda: ta sama zasada co statystyki — 0.35→0.5, nie
        // pod jeden konkretny wariant tła, tylko ogólnie pewniejsze.
        // DWUDZIESTA runda: user pokazał zrzut z zaznaczeniem — "Good
        // People Good Places" dalej WYRAŹNIE przebijało się przez slogan
        // mimo podkładki. 0.5 za mało dla tak ciemnego, odręcznego pisma —
        // 0.5→0.85, praktycznie kryjące.
        // DWUDZIESTA TRZECIA runda: "tło i góry nadal LEKKO przebijają" —
        // ostatnie +5%, 0.85→0.9.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.98, green: 0.95, blue: 0.87).opacity(0.9)))
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dane

    /// Czy nazwa przystanku brzmi jak sam punkt tranzytowy/lotnisko, nie
    /// prawdziwy cel podróży (05.09.2026, user: "jedno jest z lotniska z
    /// ktorego wylatywalem... po co lotnisko zamiast zdjecia z centrum
    /// wyspy") — te same, znane z appki nazwy ("Gatwick", "Phuket
    /// International Airport") NIE powinny reprezentować całej podróży na
    /// plakacie, jeśli podróż ma jakikolwiek INNY przystanek z realnym
    /// zdjęciem.
    /// Znane nazwy miejscowości/węzłów lotniczych które NIE zawierają
    /// dosłownie słowa "airport"/"lotnisko" w nazwie (09.09.2026, user
    /// pokazał realny przypadek: "Gatwick, England" dalej pojawiało się
    /// jako polaroid mimo istniejącego filtra tekstowego — "Gatwick" to
    /// prawdziwe miasteczko w Anglii, appka geokoduje przystanek lotniska
    /// właśnie pod tą nazwą, bez słowa "Airport"). Dopasowanie CAŁEGO
    /// tokenu nazwy miasta (nie substring), żeby nie złapać przypadkiem
    /// prawdziwego celu podróży, którego nazwa akurat zawiera jeden z tych
    /// wyrazów jako część dłuższej, innej nazwy.
    private static func looksLikeAirport(_ cityName: String) -> Bool {
        TravelAchievementsCalculator.looksLikeAirport(cityName)
    }

    private func loadPolaroids() async -> [PolaroidPhoto] {
        var seenCountries: Set<String> = []
        var candidates: [SavedStop] = []
        for trip in savedTrips.sorted(by: { $0.effectiveDate > $1.effectiveDate }) {
            let tripStopsWithPhoto = trip.stops.filter { $0.representativePhotoIdentifier != nil }
            // Prawdziwe cele podróży NAJPIERW — lotnisko/tranzyt tylko jako
            // ostatnia deska ratunku, gdy podróż nie ma żadnego innego
            // zdjęcia w ogóle.
            let realDestinations = tripStopsWithPhoto.filter { !Self.looksLikeAirport($0.cityName) }
            let pool = realDestinations.isEmpty ? tripStopsWithPhoto : realDestinations
            for stop in pool {
                let code = TravelAchievementsCalculator.countryGroupingCode(countryCode: stop.countryCode, administrativeArea: stop.administrativeArea) ?? stop.cityName
                guard !seenCountries.contains(code) else { continue }
                seenCountries.insert(code)
                candidates.append(stop)
                if candidates.count >= 5 { break }
            }
            if candidates.count >= 5 { break }
        }

        // Organiczniejszy rozrzut (06.09.2026, user: "zdjęcia mają wyglądać
        // jak fizycznie porozrzucane, nie matematycznie ułożone") — większy
        // zakres rotacji/pozycji niż poprzednio, dwa zdjęcia celowo
        // wychodzą poza dolną krawędź mapy (patrz `mapSection`).
        // 12.09.2026, trzecia runda: "dolne środkowe zdjęcie mocno nachodzi
        // na statystyki... przesunąć minimalnie wyżej" — to (20, 300, -4),
        // jedyny layout blisko środka (x≈0) I najniżej (największy y) —
        // podniesiony 300→265.
        // 13.09.2026, szósta runda: wartości Y były wyliczone pod mapę
        // 760pt wysoką — od tej pory mapa skurczyła się do 610pt (dwie
        // rundy: 760→660→610, razem -150, czyli połowa wysokości -75).
        // Bez przeskalowania zdjęcia zwisały o te same 75pt NIŻEJ pod nową,
        // mniejszą mapą niż wcześniej, nachodząc na statystyki. Wszystkie Y
        // przeskalowane × 0.8 (≈610/760), żeby zdjęcia zachowały tę samą
        // pozycję WZGLĘDEM krawędzi mapy co w oryginalnym projekcie.
        // SIÓDMA runda: mapa skurczyła się dalej do 480pt — Y przeskalowane
        // jeszcze raz (×0.787 ≈ 480/610). X przeskalowane × 0.85 —
        // "zachować rozmiar zdjęć, ale lekko zmniejszyć odstępy MIĘDZY
        // nimi" (same zdjęcia zostają 190×190, ściska się tylko rozrzut
        // pozycji, nie same karty).
        // ÓSMA runda: "lewe dolne zdjęcie optycznie nachodzi na Brașov" —
        // odsunięte od siebie (pierwsze wyżej, trzecie niżej + odrobinę w
        // bok), żeby zostawić realny odstęp mimo obrotu obu kart.
        // JEDENASTA runda: mapa 480→560, Y przeskalowane ×1.167 (560/480).
        // Potem 560→610 (pełny powrót do potwierdzonej wersji) — Y
        // przeskalowane jeszcze raz ×1.089 (610/560).
        let layouts: [(x: CGFloat, y: CGFloat, rotation: Double)] = [
            (-289, -260, -8), (272, -216, 6), (-292, 127, 5), (17, 212, -4), (281, 136, 8),
        ]

        var results: [PolaroidPhoto] = []
        for (index, stop) in candidates.enumerated() {
            let code = TravelAchievementsCalculator.countryGroupingCode(countryCode: stop.countryCode, administrativeArea: stop.administrativeArea) ?? stop.cityName
            // Ręczna podmiana zdjęcia (09.09.2026, user: "musi byc opcja
            // wybierania zdjec... powinnismy miec opcje zmiany jesli nam sie
            // ono nie podoba" — np. Gatwick jako JEDYNE zdjęcie z całej
            // podróży, bo appka nie ma z czego wybrać lepszego automatycznie)
            // — nadpisuje AUTOMATYCZNIE dobrany identyfikator zdjęcia, ale
            // NIE samego przystanku/podpisu (miejsce i kraj zostają prawdziwe,
            // zgodne z danymi podróży).
            let identifier = photoOverrides[code] ?? stop.representativePhotoIdentifier
            guard let identifier, let image = await MediaAssetLoader.thumbnail(forAssetLocalIdentifier: identifier) else { continue }
            let layout = layouts[index % layouts.count]
            // Prawdziwa nazwa kraju (rozdział Wielkiej Brytanii na 4 nacje,
            // ta sama logika co Passport/Wrapped — user: "Northern Ireland
            // nie Great Britain") + bez duplikatu gdy miasto = kraj (user:
            // "Grecja, Grecja co to w ogole").
            // 12.09.2026: bez duplikatu też gdy `cityName` jest nazwą kraju
            // w INNYM języku niż aktualny ("Grecja, Greece" — geokodowanie
            // nie znalazło miejscowości dla odległej plaży i zapisało samą
            // nazwę kraju po polsku, `countryName` policzony teraz po
            // angielsku nie pasował string-do-stringa). Patrz
            // `cityNameIsJustCountryName` — sprawdza wszystkie 27 języków.
            let countryName = TravelAchievementsCalculator.countryGroupingDisplayName(
                countryCode: stop.countryCode, administrativeArea: stop.administrativeArea,
                fallback: stop.country ?? stop.cityName
            )
            let cityIsCountry = countryName == stop.cityName
                || TravelAchievementsCalculator.cityNameIsJustCountryName(stop.cityName, countryCode: stop.countryCode)
            // 13.09.2026: "Mueang Chiang Rai District, Thailand" wyraźnie
            // dłuższy od pozostałych podpisów — skrócone do "Chiang Rai,
            // Thailand" (patrz `shortenedThaiDistrictName`).
            let displayCityName = TravelAchievementsCalculator.shortenedThaiDistrictName(stop.cityName)
            let caption = cityIsCountry ? countryName : "\(displayCityName), \(countryName)"
            results.append(PolaroidPhoto(
                id: identifier, code: code, image: image, caption: caption,
                offsetX: layout.x, offsetY: layout.y, rotation: layout.rotation,
                tripID: stop.trip?.id
            ))
        }
        return results
    }

    /// `routePaths`: trasa KAŻDEJ MIĘDZYNARODOWEJ podróży osobno, przystanki
    /// w rzeczywistej kolejności zwiedzania (11.09.2026, user: "czy mapa
    /// moze pokazywac rzeczywista siec podrozy"). Wcześniej `flightPathOverlay`
    /// łączył WSZYSTKIE przystanki ze WSZYSTKICH podróży jedną ciągłą linią —
    /// realny bug: rysował fikcyjny "lot" między ostatnim przystankiem
    /// jednej podróży a pierwszym zupełnie innej, plus `trip.stops` to
    /// surowa relacja SwiftData bez gwarancji kolejności, więc nawet trasa
    /// POJEDYNCZEJ podróży mogła się zygzakować losowo. Teraz każda podróż
    /// sortowana po `order` i zwracana jako osobna pod-trasa.
    ///
    /// 12.09.2026, TRZECIA runda feedbacku (narzeczona usera, dwie
    /// wiadomości): "usunąć kilka linii z przelotów" (11.09) było za mało —
    /// przy 40-80 krajach zarówno linie JAK I pinezki muszą się skalować,
    /// nie tylko linie. Docelowy system: **max 3-5 linii tras** (próg wg
    /// liczby lotów: ≤10 → wszystkie, 11-25 → top 5, 25+ → top 3, ranking
    /// po CAŁKOWITYM dystansie podróży — najdłuższa/najbardziej efektowna
    /// trasa jak "Europe → Thailand" wygrywa) i **max 12-15 pinezek**
    /// (ranking `TravelRarityScore`, dedup po zaokrąglonej współrzędnej —
    /// dwa prawie-identyczne przystanki w tym samym mieście liczą się raz).
    ///
    /// `priorityTripIDs` (12.09.2026, user: "moze mapa bedzie pokazywac
    /// loty ktore mamy na zdjeciach") — podróże które dostarczyły polaroid
    /// (`loadPolaroids`) są WYMUSZONE na pierwszym miejscu w obu rankingach
    /// (tras i pinezek), reszta miejsc dogrywa się rarity score/dystansem
    /// jak dotąd. Bez tego mapa i zdjęcia opowiadały dwie NIEZALEŻNE,
    /// czasem sprzeczne historie (zdjęcie z Tajlandii, ale mapa podświetla
    /// zupełnie inne, "rzadsze" kraje bez zdjęcia).
    private func renderMapSnapshot(priorityTripIDs: Set<UUID>) async -> (image: UIImage?, points: [CGPoint], routePaths: [[CGPoint]], countryFills: [CountryFillShape]) {
        let orderedTrips = savedTrips.map { $0.stops.sorted { $0.order < $1.order } }
        let coordinates = orderedTrips.flatMap { $0.map(\.coordinate) }
        guard !coordinates.isEmpty else { return (nil, [], [], []) }

        func isPriority(_ stops: [SavedStop]) -> Bool {
            guard let tripID = stops.first?.trip?.id else { return false }
            return priorityTripIDs.contains(tripID)
        }
        func tripDistance(_ stops: [SavedStop]) -> Double {
            stops.reduce(0) { $0 + $1.legDistanceKm }
        }

        let internationalTrips = orderedTrips.filter { stops in
            let codes = Set(stops.compactMap {
                TravelAchievementsCalculator.countryGroupingCode(countryCode: $0.countryCode, administrativeArea: $0.administrativeArea)
            })
            return codes.count >= 2
        }
        let rankedTrips = internationalTrips.sorted { a, b in
            let pa = isPriority(a), pb = isPriority(b)
            if pa != pb { return pa }
            return tripDistance(a) > tripDistance(b)
        }
        let home = homeCoordinate
        let homeC = homeContinent
        var seenKeys: Set<String> = []
        var dedupedStops: [SavedStop] = []
        for stop in orderedTrips.flatMap({ $0 }) {
            let key = String(format: "%.2f,%.2f", stop.coordinate.latitude, stop.coordinate.longitude)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            dedupedStops.append(stop)
        }
        // 12.09.2026, druga runda feedbacku: "maksymalnie 10-12 pinów" —
        // cap 15→12.
        let pinCap = 12
        let pinStops: [SavedStop]
        if dedupedStops.count <= pinCap {
            pinStops = dedupedStops
        } else {
            pinStops = Array(dedupedStops.sorted { a, b in
                let pa = a.trip.map { priorityTripIDs.contains($0.id) } ?? false
                let pb = b.trip.map { priorityTripIDs.contains($0.id) } ?? false
                if pa != pb { return pa }
                guard let home else { return false }
                return TravelRarityScore.score(coordinate: a.coordinate, countryCode: a.countryCode, home: home, homeContinent: homeC, isFavorite: a.trip?.isFavorite ?? false, visitDate: a.arrivalDate) >
                       TravelRarityScore.score(coordinate: b.coordinate, countryCode: b.countryCode, home: home, homeContinent: homeC, isFavorite: b.trip?.isFavorite ?? false, visitDate: b.arrivalDate)
            }.prefix(pinCap))
        }

        // 12.09.2026, druga runda feedbacku: "mapa powinna być tłem dla
        // wspomnień, nie głównym wykresem lotów" — twardy limit 3 (było
        // 3-5), a gdy mapa i tak ma dużo pinów (gęsto), jeszcze mniej linii
        // (2), żeby nie rywalizowały wizualnie z pinezkami/zdjęciami.
        // TRZECIA runda: "zostawić maksymalnie dwie" — twardy limit 2
        // zawsze, niezależnie od gęstości pinów (podświetlone kraje +
        // pinezki już niosą resztę historii, linie to czysta dekoracja).
        let maxRoutes = 2
        let cappedTrips = Array(rankedTrips.prefix(maxRoutes))

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        // 13.09.2026, punkt 2 z dużego przeglądu: "zdjęcia zasłaniają sporą
        // część kontynentów, dopilnuj żeby zaznaczenia krajów nie były
        // WYŁĄCZNIE pod Polaroidami" — bez ruszania pozycji zdjęć/rozmiaru
        // mapy (jak poprosił user).
        // TRZYDZIESTA runda: user — "co jeśli mapę (Europę) przesunęli
        // byśmy delikatnie w prawo?". Zamiast twardego przesunięcia
        // działającego tylko przypadkiem dla TYCH konkretnych danych:
        // środek liczony dotąd jako środek SKRAJNYCH punktów (min/max) —
        // ciągnie widok w stronę pojedynczych odległych wyjazdów
        // (Tajlandia, Katar), spychając gęsty klaster (Europa) w bok.
        // Zamiana na ŚREDNIĄ wszystkich odwiedzonych współrzędnych —
        // naturalnie centruje widok tam, gdzie jest NAJWIĘCEJ krajów, nie
        // tam gdzie są skrajności. Rozpiętość (span) liczona OSOBNO jako
        // najdalszy punkt od TEGO nowego środka (nie od starego środka
        // min/max) — inaczej odległe wyjazdy wypadłyby poza kadr, bo
        // `MKCoordinateRegion` jest zawsze symetryczny wokół środka.
        // TRZYDZIESTA PIERWSZA runda (wycofana): zamiana ŚREDNIEJ na
        // medianę + rozmyta poświata na krajach — user: poprzednia wersja
        // (sama średnia, bez mediany/rozmycia) była wyraźnie lepsza.
        // Cofnięte.
        // TRZYDZIESTA DRUGA runda: user powtórzył dokładnie te same dwa
        // punkty co w 30-31 rundzie — "średnia to GŁÓWNE ustawienie" (nie
        // zamieniać na medianę) + "ograniczenie MAKSYMALNEGO przesunięcia
        // środka" (osobny, jawny limit, nie inna miara statystyczna).
        // Realizacja dosłowna: środek = ŚREDNIA (jak było w 30. rundzie),
        // ale docięta (`clampedTowardMedian`) tak, żeby nie mogła odjechać
        // od mediany (odpornej na pojedyncze skrajności, liczonej tylko
        // jako "kotwica" limitu, NIE jako sam środek) o więcej niż 15°.
        // Przy jednym dalekim wyjeździe (Australia) na tle klastra w
        // Europie różnica mean-median byłaby duża — limit ją przycina;
        // przy normalnym rozrzucie (jak dziś: Europa+Tajlandia+Katar)
        // różnica jest mała i limit nic nie zmienia, więc środek to
        // praktycznie czysta średnia.
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        func clampedTowardMedian(_ mean: Double, median: Double, maxShift: Double) -> Double {
            let diff = mean - median
            guard abs(diff) > maxShift else { return mean }
            return median + (diff > 0 ? maxShift : -maxShift)
        }
        let meanLat = lats.reduce(0, +) / Double(lats.count)
        let meanLon = lons.reduce(0, +) / Double(lons.count)
        let maxCenterShiftDegrees = 15.0
        let centerLat = clampedTowardMedian(meanLat, median: median(lats), maxShift: maxCenterShiftDegrees)
        let centerLon = clampedTowardMedian(meanLon, median: median(lons), maxShift: maxCenterShiftDegrees)
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let maxLatDelta = lats.map { abs($0 - centerLat) }.max() ?? 0
        let maxLonDelta = lons.map { abs($0 - centerLon) }.max() ?? 0
        // 1.8 (poprzednia runda): "oddalenie kadru... więcej podświetlonych
        // krajów wystaje poza stałe rogi zdjęć".
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLatDelta * 2 * 1.8, 40),
            longitudeDelta: max(maxLonDelta * 2 * 1.8, 60)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1000, height: 800)
        options.mapType = .mutedStandard
        options.showsBuildings = false
        // 13.09.2026: "usuń przypadkowe/mało czytelne napisy geograficzne" —
        // usuwa ikonki/podpisy punktów zainteresowania (restauracje, sklepy
        // itp.), to jedyna kategoria etykiet którą Apple pozwala wyłączyć
        // przez publiczne API. Nazwy kontynentów/krajów/miast są wypalone w
        // stylu bazowej mapy i nie da się ich pojedynczo wyłączyć — mniejsza
        // mapa (patrz `.frame(height: 660)` w `mapSection`) ogranicza ich
        // widoczną liczbę naturalnie.
        options.pointOfInterestFilter = .excludingAll
        // 12.09.2026, feedback narzeczonej usera: mapa wyszła "nocna" na
        // urządzeniu testera, mimo że nigdzie w kodzie tego nie wybraliśmy —
        // przyczyna: bez jawnego `traitCollection`, `MKMapSnapshotter` bierze
        // AKTUALNY tryb wyglądu urządzenia w momencie renderu, więc wygląd
        // plakatu zależał od tego, czy dany tester ma Dark Mode włączony
        // (niezamierzona niespójność między userami) — fix wtedy: wymuszone
        // NA STAŁE na `.dark`.
        // 13.09.2026: user poprosił o przywrócenie prawdziwego wyboru
        // dzień/noc (appka MIAŁA tę opcję dawniej) — zamiast losowego
        // "wycieku" z ustawień urządzenia, świadomy wybór wg
        // `isDaytimeMap` (lokalna godzina, ustawiona raz w `.task`).
        options.traitCollection = UITraitCollection(userInterfaceStyle: isDaytimeMap ? .light : .dark)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return (nil, [], [], []) }
        let points = pinStops.map { snapshot.point(for: $0.coordinate) }
        let routePaths = cappedTrips.map { trip in trip.map { snapshot.point(for: $0.coordinate) } }

        // 12.09.2026, Warstwa 1 feedbacku narzeczonej: "podświetlone kraje =
        // ogólna historia podróżowania". Licz ODWIEDZONE PODRÓŻE (nie
        // przystanki — jedna wycieczka z kilkoma miastami w tym samym kraju
        // to jedna wizyta, nie kilka), żeby "kraj z większą liczbą podróży =
        // ciemniejszy" faktycznie znaczyło liczbę WYCIECZEK.
        var tripsByCountry: [String: Set<UUID>] = [:]
        // 13.09.2026: user zgłosił podświetlony kraj w Ameryce Południowej,
        // mimo że tam nigdy nie był. Przyczyna sprawdzona bezpośrednio w
        // `WorldCountryBoundaries.json`: kod "FR" to w tych danych GRANIC
        // (Natural Earth) jeden wpis obejmujący 10 rozłącznych poligonów —
        // kontynentalna Francja + Korsyka, ale TAKŻE Reunion, Majotta,
        // Gwadelupa, Martynika i Gujana Francuska (lat 2–6°N, lon -54…-52°W
        // — realnie w Ameryce Południowej). Sam kod kraju (`FR`) jest
        // poprawny — user faktycznie miał 1 przystanek w kontynentalnej
        // Francji — ale wcześniej wypełnialiśmy WSZYSTKIE poligony danego
        // kodu, więc razem z Francją podświetlały się też jej zamorskie
        // terytoria po drugiej stronie świata. Zbieramy tu realne
        // współrzędne odwiedzonych przystanków per kraj, żeby niżej
        // (`countryFills`) wyrenderować tylko te poligony kraju, które
        // faktycznie leżą blisko miejsca, gdzie user był — nie każdy
        // rozłączny kawałek zapisany pod tym samym kodem ISO.
        var visitedCoordinatesByCountry: [String: [CLLocationCoordinate2D]] = [:]
        for stops in orderedTrips {
            guard let tripID = stops.first?.trip?.id else { continue }
            for code in Set(stops.compactMap(\.countryCode)) {
                tripsByCountry[code, default: []].insert(tripID)
            }
            for stop in stops {
                guard let code = stop.countryCode else { continue }
                visitedCoordinatesByCountry[code, default: []].append(stop.coordinate)
            }
        }
        let homeCode = homeCountryCode
        // Poligon liczy się jako "odwiedzony", jeśli jego środek leży w
        // promieniu tego progu od CHOĆ JEDNEGO realnie odwiedzonego
        // przystanku tego kraju — odcina rozłączne zamorskie terytoria
        // (Gujana Francuska ~7000 km od Paryża) zostawiając jednocześnie z
        // zapasem bliskie wyspiarskie/eksklawowe kawałki tego samego kraju
        // (np. Wyspy Kanaryjskie ~1700 km od Madrytu, Kaliningrad).
        let overseasTerritoryMaxDistanceKm = 2500.0
        // 12.09.2026, druga runda feedbacku (nocna mapa): poprzednie
        // stonowane niebiesko-zielone wypełnienie + ciemny atramentowy
        // obrys były dobrane pod JASNĄ mapę — na wymuszonej teraz nocnej
        // (patrz `options.traitCollection` wyżej) praktycznie znikały.
        // Odwiedzone kraje = ciepły, przygaszony bursztyn (jasny na ciemnym
        // tle = od razu widoczny), dom = kontrastujący turkus (żeby nie
        // mylić "gdzie mieszkam" z "gdzie byłem" mimo podobnej jasności).
        // Obrys: kremowy zamiast atramentowego — cienki, ale realnie
        // widoczny na granatowo-zielonej nocnej mapie.
        // 12.09.2026, trzecia runda: "cieplejszy kolor odwiedzonych krajów...
        // lekko rozjaśnić granice" — bursztyn cieplejszy (więcej czerwieni,
        // mniej niebieskiego), obrys jaśniejszy.
        // 13.09.2026: dwie OSOBNE palety — ta sama zasada (bursztyn/turkus)
        // na nocnej mapie znika/traci sens na jasnej bazie. Wersja dzienna
        // wraca do stonowanego niebiesko-zielonego + ciepłego złota z tego
        // samego mockupu co przed wprowadzeniem nocnego trybu — dobrana pod
        // jasne, kremowe tło mapy (`.mutedStandard` w `.light`), nie pod
        // granatowo-zielone.
        // DWUDZIESTA SZÓSTA runda: "odwiedzone kraje zlewają się z jasną
        // mapą... ciepły złoto-brązowy/ochrowy, ciemniejszy obrys, więcej
        // kontrastu — ale bez jaskrawości". Dzień: odwiedzone = ochra, dom
        // = dawny niebiesko-zielony w roli KONTRASTU (ten sam schemat
        // "ciepłe = odwiedzone, chłodne = dom" co w wersji nocnej, role
        // kolorów zamienione między trybami).
        // DWUDZIESTA SIÓDMA runda: user — ochra z poprzedniej rundy "zbyt
        // ciężka, wygląda jak plama". Skorygowane w stronę "starego
        // mosiądzu": jaśniejszy, cieplejszy złoty ton (mniej brązu, więcej
        // złota) + dużo mniejsze krycie (efekt delikatnej poświaty, nie
        // płaskiego bloku) + miększy, cieplejszy obrys zamiast niemal
        // czarnego. Prawdziwa tekstura/ziarno w obrębie kraju wymagałaby
        // generowanego wzoru maskowanego kształtem kraju — nieproporcjonalny
        // nakład względem efektu; ten sam "vintage" charakter osiągnięty
        // samą przezroczystością/miękkością koloru.
        // TRZYDZIESTA PIERWSZA runda: "mocniejszy, ale elegancki kolor" —
        // bardziej nasycone złoto (mniej pastelowe, więcej głębi), plus
        // poświata z `countryFillsOverlay` robi resztę roboty przy
        // kontraście bez podnoszenia samego wypełnienia do ciężkiego bloku.
        let visitedTint = isDaytimeMap
            ? Color(red: 0.78, green: 0.58, blue: 0.24)
            : Color(red: 0.96, green: 0.76, blue: 0.4)
        let homeTint = isDaytimeMap
            ? Color(red: 0.28, green: 0.46, blue: 0.5)
            : Color(red: 0.35, green: 0.72, blue: 0.68)
        let creamStroke = isDaytimeMap
            ? Color(red: 0.42, green: 0.31, blue: 0.14)
            : Color(red: 0.96, green: 0.92, blue: 0.82)
        let countryFills: [CountryFillShape] = tripsByCountry.compactMap { code, tripIDs in
            guard let boundary = WorldCountryBoundaries.all[code] else { return nil }
            let visitedCoordinates = visitedCoordinatesByCountry[code] ?? []
            let nearbyPolygons = boundary.polygons.filter { polygon in
                guard !visitedCoordinates.isEmpty else { return true }
                let allPoints = polygon.flatMap { $0 }
                guard !allPoints.isEmpty else { return false }
                let centerLat = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count)
                let centerLon = allPoints.map(\.longitude).reduce(0, +) / Double(allPoints.count)
                let polygonCenter = CLLocation(latitude: centerLat, longitude: centerLon)
                return visitedCoordinates.contains { visited in
                    let distanceKm = polygonCenter.distance(from: CLLocation(latitude: visited.latitude, longitude: visited.longitude)) / 1000
                    return distanceKm <= overseasTerritoryMaxDistanceKm
                }
            }
            let projectedPolygons = nearbyPolygons.map { polygon in
                polygon.map { ring in ring.map { snapshot.point(for: $0) } }
            }
            guard !projectedPolygons.isEmpty else { return nil }
            let isHome = code == homeCode
            // Wizyta 1x: delikatniejszy odcień, 2+ wizyt: ten sam odcień,
            // mocniej wysycony — "kraj z większą liczbą podróży = nieco
            // ciemniejszy" (nie inny kolor, sama intensywność). Na ciemnej
            // mapie potrzeba więcej krycia żeby kolor "zaświecił"; na
            // jasnej te same wartości wyglądałyby zbyt mocno — niższe.
            // DWUDZIESTA SZÓSTA runda: "więcej kontrastu" — dzienne opacity
            // podniesione (0.24/0.32/0.4 → 0.32/0.42/0.45), nocne lekko
            // podniesione też (widoczność na ciemnym tle, nie tylko kolor).
            // DWUDZIESTA SIÓDMA runda: user — za mocno, "wygląda jak plama".
            // Wyraźnie w dół, efekt delikatnej poświaty zamiast płaskiego
            // bloku (0.32-0.45→0.2-0.28 dzień, 0.36-0.52→0.26-0.34 noc).
            // DWUDZIESTA ÓSMA runda: poszliśmy za daleko w drugą stronę —
            // "za blado, nie od razu wiadomo które kraje są zaznaczone".
            // Złoty środek między ciężkim blokiem (26) a ledwo widoczną
            // poświatą (27) — kolor/obrys zostają te same (już dobrze
            // dobrane), podniesione tylko krycie.
            // TRZYDZIESTA PIERWSZA runda: user — dalej "za mało
            // kontrastowe". Jeszcze raz w górę, tym razem razem z realną
            // poświatą (`countryFillsOverlay`) i bardziej nasyconym
            // kolorem, więc efekt łączny powinien być wyraźnie mocniejszy
            // niż w 28. rundzie mimo że samo wypełnienie rośnie umiarkowanie.
            let opacity: Double = isDaytimeMap
                ? (isHome ? 0.44 : (tripIDs.count >= 2 ? 0.48 : 0.4))
                : (isHome ? 0.48 : (tripIDs.count >= 2 ? 0.52 : 0.44))
            return CountryFillShape(
                code: code,
                fill: (isHome ? homeTint : visitedTint).opacity(opacity),
                stroke: creamStroke.opacity(isDaytimeMap ? 0.65 : 0.55),
                polygons: projectedPolygons
            )
        }

        return (snapshot.image, points, routePaths, countryFills)
    }
}

private struct PolaroidPhoto: Identifiable, PosterPolaroidDescribable {
    let id: String
    /// Kod grupowania kraju (`TravelAchievementsCalculator.countryGroupingCode`)
    /// — klucz do `photoOverrides`, żeby ręczna podmiana zdjęcia wiedziała
    /// KTÓRY slot zmienić.
    let code: String
    let image: UIImage
    let caption: String
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotation: Double
    /// 12.09.2026, user: "moze mapa bedzie pokazywac loty ktore mamy na
    /// zdjeciach" — żeby mapa i polaroidy opowiadały JEDNĄ spójną historię
    /// zamiast dwóch niezależnie dobranych zestawów (zdjęcia z jednych
    /// podróży, trasy/pinezki na mapie z zupełnie innych). `renderMapSnapshot`
    /// premiuje te same podróże co tutaj.
    let tripID: UUID?
}

private struct PolaroidView: View {
    let polaroid: PolaroidPhoto

    /// Deterministyczny "przypadkowy" wygląd taśmy per zdjęcie — wyprowadzony
    /// z hasha `polaroid.id` (identyfikator zdjęcia z biblioteki, stały
    /// między odświeżeniami plakatu), żeby każdy polaroid miał inny kąt/
    /// pozycję/przezroczystość taśmy, ale ta sama fotka zawsze wygląda tak
    /// samo (nie migocze losowo przy każdym re-renderze SwiftUI).
    private var tapeJitter: (angle: Double, width: CGFloat, offsetX: CGFloat, opacity: Double) {
        var hasher = Hasher()
        hasher.combine(polaroid.id)
        let seed = abs(hasher.finalize())
        let angle = -8.0 + Double(seed % 17)
        let width = 64.0 + CGFloat(seed / 17 % 13)
        let offsetX = -6.0 + CGFloat(seed / 221 % 13)
        let opacity = 0.8 + Double(seed / 2873 % 16) / 100
        return (angle, width, offsetX, opacity)
    }

    /// 11.09.2026: powrót do prostej, kwadratowej karty (user: "nie bedziemy
    /// sie motac z ramkami ktore nie mozemy dopasowac do zdjec wracamy do
    /// kwadratowych ktore byly na poczatku") — po trzech rundach walki z
    /// `PosterFrameStyle` (ramki z arkusza "Photo Frames Collection 1/4":
    /// za małe zdjęcia, potem prawdziwe maski kształtu, wciąż user widział
    /// niedopasowanie) decyzja: zrezygnować z dekoracyjnych ramek na
    /// zdjęciach w ogóle, nie kolejna łatka. `PosterFrameStyle.swift`
    /// zostaje nieużywany w projekcie (assety w `Assets.xcassets` też),
    /// na wypadek gdyby temat wrócił w innej formie.
    var body: some View {
        VStack(spacing: 10) {
            // 12.09.2026, druga runda: "zdjęcia nadal zasłaniają dużą
            // część mapy... zmniejszyłbym o 5-10%" — 220→200 (~9%).
            // TRZECIA runda: "zmniejszyć je minimalnie, około 5%" — 200→190,
            // liczba zdjęć (5) dalej bez zmian.
            Image(uiImage: polaroid.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 190, height: 190)
                .clipped()
            Text(polaroid.caption)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(1)
                .padding(.bottom, 4)
        }
        .padding(10)
        .background(Color.white)
        // 13.09.2026, piąta runda: "taśma trochę zbyt równa i cyfrowa...
        // lekko różne kąty taśmy, delikatne zużycie, subtelne cienie" —
        // odrobinę mocniejszy/bliższy cień pod samym zdjęciem (bardziej
        // "leży na papierze", nie unosi się nad nim).
        .shadow(color: .black.opacity(0.32), radius: 7, y: 5)
        // Prawdziwa, wycięta taśma washi zamiast samego cienia (06.09.2026,
        // user dostarczył zestaw zdjęć) — jakby ktoś fizycznie przykleił
        // polaroid do strony. Kąt/pozycja/przezroczystość taśmy DETERMINISTYCZNIE
        // wyprowadzone z `polaroid.id` (13.09.2026: "taśma zbyt równa i
        // cyfrowa" — każde zdjęcie ma inny, ale STAŁY między odświeżeniami
        // "przypadkowy" wygląd, nie identyczną taśmę na każdym polaroidzie).
        .overlay(alignment: .top) {
            Image("TravelJourneyTape")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: tapeJitter.width)
                .rotationEffect(.degrees(tapeJitter.angle))
                .offset(x: tapeJitter.offsetX, y: -14)
                .opacity(tapeJitter.opacity)
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
        }
    }
}

private struct CountryStamp {
    let code: String
    let name: String
    let flag: String
    /// Współrzędna reprezentatywnego przystanku w tym kraju — do
    /// `TravelRarityScore` (12.09.2026), nie do wyświetlania.
    let coordinate: CLLocationCoordinate2D
    /// Czy KTÓRAKOLWIEK podróż do tego kraju jest oznaczona serduszkiem
    /// (`SavedTrip.isFavorite`) — pkt 5 hierarchii rarity score.
    var isFavorite: Bool = false
    /// Data przyjazdu reprezentatywnego przystanku — pkt 6 hierarchii
    /// (najsłabszy czynnik, tylko rozstrzyga remisy).
    var visitDate: Date?
}

/// Jeden odwiedzony kraj zaprojektowany na punkty mapy — gotowy do
/// narysowania (12.09.2026, patrz `renderMapSnapshot`/`countryFillsOverlay`).
private struct CountryFillShape: Identifiable {
    var id: String { code }
    let code: String
    let fill: Color
    let stroke: Color
    /// Każdy element to jeden poligon kraju (wyspy/eksklawy osobno),
    /// każdy poligon to lista pierścieni (pierwszy = obrys, kolejne =
    /// dziury), już w PUNKTACH mapy (`snapshot.point(for:)`), nie
    /// współrzędnych geograficznych.
    let polygons: [[[CGPoint]]]
}

/// Statystyki CAŁEGO archiwum podróży (nie jednego roku jak `TravelWrapped`)
/// — ten sam mechanizm grupowania krajów (`countryGroupingCode`), więc
/// liczba krajów tutaj ZAWSZE zgadza się z Travel Passport/Explorer Score.
private struct JourneyStats {
    let countryCount: Int
    let tripCount: Int
    let totalKm: Int
    let flightCount: Int

    init(from trips: [SavedTrip]) {
        let allStops = trips.flatMap(\.stops)
        countryCount = Set(allStops.compactMap {
            TravelAchievementsCalculator.countryGroupingCode(countryCode: $0.countryCode, administrativeArea: $0.administrativeArea)
        }).count
        tripCount = trips.count
        totalKm = Int(allStops.reduce(0) { $0 + $1.legDistanceKm }.rounded())
        // 13.09.2026: user zgłosił dokładnie 2× za dużo lotów na plakacie
        // (56 zamiast 28 ze "Statystyk życiowych"). Przyczyna sprawdzona na
        // żywych danych z urządzenia: KAŻDY pierwszy przystanek podróży
        // (`order == 0`, punkt startowy) ma `transportRawValue == "plane"`
        // jako wartość domyślną/pozostałość, mimo że nie ma żadnego
        // realnego lotu DO niego (`legDistanceKm == 0.0` zawsze dla
        // `order == 0`, potwierdzone SQL-em na `ZSAVEDSTOP`). Liczyliśmy
        // tu WSZYSTKIE przystanki z tagiem "plane", w tym ten sztuczny —
        // stąd +1 fantomowy lot na KAŻDĄ z 28 podróży = dokładnie +28,
        // czyli 56 zamiast 28. `TravelAchievements.swift` (`stopsWithRealLeg`)
        // już dawno poprawnie to filtrował (`order > 0 && legDistanceKm > 0`)
        // — ten sam warunek doklejony tutaj, żeby liczba lotów na plakacie
        // ZAWSZE zgadzała się z tą w Statystykach życiowych (ten sam duch co
        // `countryCount` wyżej, świadomie używający tego samego mechanizmu
        // co Passport/Explorer Score).
        flightCount = allStops.filter { $0.order > 0 && $0.legDistanceKm > 0 && $0.transportRawValue == TransportMode.plane.rawValue }.count
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
