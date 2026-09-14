import MapKit
import AVFoundation
import UIKit
import Photos

/// Renderuje EKSPORT WIDEO Travel Map (globus, trasa, ikona pojazdu,
/// etykiety) — dyskretne przechwytywanie klatek ukrytej `MKMapView`.
///
/// Historia (27.07.2026): najpierw `MKMapSnapshotter` per odcinek (jeden
/// statyczny zrzut), potem `MKMapSnapshotter` per klatka z kamerą — oba
/// wyglądały INACZEJ niż żywy podgląd, bo `MKMapSnapshotter` w ogóle nie
/// umie wyrenderować widoku globusa (widoczna krzywizna Ziemi) — to osobny
/// silnik renderowania niż żywa `Map`, nie tylko inny sposób wołania tej
/// samej rzeczy. User: "dlaczego zapis zmienia wygląd?!" — bo to była
/// dosłownie inna rzecz. Naprawione przejściem na prawdziwy `MKMapView`.
///
/// **30.07.2026 — unifikacja z ówczesnym podglądem (WYSIWYG), potem
/// 31.07.2026 podgląd dostał WŁASNY, natywnie animowany silnik.** Przez
/// jeden dzień (30.07.2026) ten sam kod (`renderFrames`) obsługiwał i
/// eksport, i żywy podgląd — gwarancja zera rozjazdów kosztem płynności
/// podglądu (dyskretne skoki kamery zamiast animacji). 31.07.2026: podgląd
/// przeszedł na osobną `TravelLiveMapView` (prawdziwa, animowana `setCamera`)
/// — TEN plik zostaje jedynym miejscem produkującym plik wideo. Zero ryzyka
/// nowego rozjazdu mimo dwóch implementacji: obie nadal karmią się TYMI
/// SAMYMI wartościami z `TravelCinematics`/`RouteProvider`/`VehicleIconSet`
/// — pilnujemy zgodności WARTOŚCI, nie techniki renderowania.
enum TravelMapVideoRenderer {
    /// Ostatni profil wydajności eksportu (patrz `printProfile`) — user nie
    /// ma dostępu do konsoli Xcode na telefonie, więc oprócz `print()`
    /// appka pokazuje to też wprost w alercie po zapisie
    /// (`TravelMapAnimationView`), żeby dało się to po prostu przeczytać/
    /// przekazać dalej. Pojedynczy zapis na raz w praktyce (eksport blokuje
    /// UI zapisu), więc zwykły `static var` wystarcza.
    @MainActor
    static var lastProfileSummary: String?

    /// TYMCZASOWE (01.08.2026) — user zgłosił (3. raz): kamera "wystrzeliwuje"
    /// natychmiast po kadrze startowym, mimo że oba kadry proszą o TEN SAM
    /// dystans/pochylenie. Zamiast dalej zgadywać: zbieramy pierwsze kilka
    /// rzeczywistych rozjazdów żądany↔faktyczny dystans (już istniejący
    /// diagnostyczny `print` w `captureBaseImage`, teraz też zapisywany tu,
    /// żeby user mógł to przeczytać bez konsoli Xcode) i pokazujemy w
    /// alercie po zapisie. Usunąć po znalezieniu/naprawieniu przyczyny.
    @MainActor
    static var lastCameraDebug: String?

    enum RenderError: Error {
        case notEnoughStops
        case writerFailed(String)
        case captureSetupFailed
    }

    private struct RenderSession {
        let mapView: MKMapView
        let renderDelegate: MapRenderDelegate
        let captureWindow: UIWindow
    }

    /// Ukryte okno w NORMALNYCH współrzędnych ekranu (0,0), ale bardzo niski
    /// `windowLevel` — więc jest wizualnie "pod spodem" właściwego okna
    /// appki i user go nigdy nie widzi. Używane i przez eksport, i przez
    /// podgląd — w OBU przypadkach user i tak widzi tylko SKOMPONOWANY obraz
    /// (`composite()`), nigdy sam surowy widok mapy, więc nie ma potrzeby
    /// pokazywać go naprawdę na ekranie. POPRZEDNIA wersja (przed 30.07)
    /// pozycjonowała okno milion punktów poza ekranem, co najpewniej
    /// powodowało że system w ogóle nie renderował w nim zawartości (stąd
    /// sygnał "mapa gotowa" nigdy nie przychodził i każda klatka czekała
    /// pełny timeout).
    @MainActor
    private static func makeSession(size: CGSize, mapTheme: MapTheme) throws -> RenderSession {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw RenderError.captureSetupFailed
        }
        let captureWindow = UIWindow(windowScene: windowScene)
        captureWindow.frame = CGRect(origin: .zero, size: size)
        captureWindow.windowLevel = UIWindow.Level(rawValue: -10_000)
        captureWindow.isUserInteractionEnabled = false

        let mapView = MKMapView(frame: CGRect(origin: .zero, size: size))
        // `preferredConfiguration`, NIE `mapType` — jedyna właściwość, która
        // włącza `elevationStyle: .realistic` (widok globusa z krzywizną).
        mapView.preferredConfiguration = mapTheme.mapConfiguration
        // Bez jawnego, szerokiego `cameraZoomRange` żądany dystans mógł być
        // po cichu przycinany do czegoś dużo mniejszego.
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 20_000_000)
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = mapTheme.pointOfInterestFilter

        let hostViewController = UIViewController()
        hostViewController.view = mapView
        captureWindow.rootViewController = hostViewController
        captureWindow.isHidden = false

        let renderDelegate = MapRenderDelegate()
        mapView.delegate = renderDelegate

        return RenderSession(mapView: mapView, renderDelegate: renderDelegate, captureWindow: captureWindow)
    }

    /// Prefetch kafelków CAŁEJ trasy na OSOBNEJ ukrytej `MKMapView` —
    /// wołane fire-and-forget z `renderFrames`, patrz komentarz przy
    /// wywołaniu (12.08.2026). Duplikuje trasowanie (`RouteProvider.route`)
    /// i matematykę pozycji kamery zamiast dzielić stan z główną pętlą —
    /// świadomie: to CAŁKOWICIE osobny task, dzielenie stanu (np.
    /// przekazywanie już policzonych `path`) między dwoma współbieżnymi
    /// konsumentami komplikowałoby główną pętlę, wielokrotnie dostrajaną
    /// dziś i wcześniej pod realne bugi — user chciał ją zostawić
    /// NIETKNIĘTĄ. Koszt podwójnego routingu jest pomijalny (jedno
    /// zapytanie API per odcinek, nie tysiące kafelków) w porównaniu do
    /// potencjalnego zysku.
    @MainActor
    private static func warmupTileCache(
        stops: [TripStop], speedMultiplier: Double, mapTheme: MapTheme,
        captureInterval: Int, stepsPerLeg: Int, size: CGSize
    ) async {
        guard let session = try? makeSession(size: size, mapTheme: mapTheme) else { return }
        let mapView = session.mapView
        let renderDelegate = session.renderDelegate
        defer { session.captureWindow.isHidden = true }

        func flatConfiguration() -> MKMapConfiguration {
            switch mapTheme {
            case .satellite:
                return MKHybridMapConfiguration(elevationStyle: .flat)
            case .minimalWhite:
                return mapTheme.mapConfiguration
            }
        }

        var lastUsedFlatElevation: Bool?

        for legIndex in 0..<max(0, stops.count - 1) {
            if Task.isCancelled { return }
            let from = stops[legIndex]
            let to = stops[legIndex + 1]
            guard let fromCoordinate = from.coordinate, let toCoordinate = to.coordinate else { continue }

            let result = await RouteProvider.route(from: fromCoordinate, to: toCoordinate, transport: to.transport)
            let path = RouteProvider.cinematicPath(result.path)
            let legDistanceKm = result.distanceKm
            let legCameraCenter: CLLocationCoordinate2D? = (to.transport == .plane && legDistanceKm <= TravelCinematics.longFlightFollowThresholdKm)
                ? RouteProvider.midpoint(from: fromCoordinate, to: toCoordinate)
                : nil
            // Musi być DOKŁADNIE ta sama wartość co główna pętla (12.08.2026,
            // po cofnięciu eksperymentu "rzadziej dla lądu/wody" — patrz
            // komentarz tam) — prefetch ma odwiedzać DOKŁADNIE te same
            // pozycje co realne przechwycenia, nie więcej/mniej.
            let effectiveCaptureInterval = captureInterval
            let steps = max(8, Int(Double(stepsPerLeg) / max(1.0, speedMultiplier)))
            let useFlatElevation = to.transport == .plane

            for step in 0...steps {
                if Task.isCancelled { return }
                guard step % effectiveCaptureInterval == 0 || step == steps else { continue }
                let rawProgress = Double(step) / Double(steps)
                let progress = TravelCinematics.easeInOutCubic(rawProgress)
                // Ta sama interpolacja co główna pętla (12.08.2026, patrz
                // `RouteProvider.interpolate`) — żeby prefetch celował w
                // dokładnie tę samą (płynną) pozycję co realne przechwycenie.
                let rawIndex = Double(path.count - 1) * progress
                let pointIndex = Int(rawIndex)
                let nextIndex = min(path.count - 1, pointIndex + 1)
                let point = RouteProvider.interpolate(from: path[pointIndex], to: path[nextIndex], fraction: rawIndex - Double(pointIndex))
                let frameState = TravelCinematics.frameState(progress: progress, legDistanceKm: legDistanceKm, transport: to.transport)

                if lastUsedFlatElevation != useFlatElevation {
                    mapView.preferredConfiguration = useFlatElevation ? flatConfiguration() : mapTheme.mapConfiguration
                    lastUsedFlatElevation = useFlatElevation
                }
                mapView.camera = MKMapCamera(
                    lookingAtCenter: legCameraCenter ?? point, fromDistance: frameState.cameraDistance,
                    pitch: frameState.cameraPitch, heading: 0
                )
                // Krótszy limit niż główna pętla (10s) — to tylko przewaga
                // startowa, nie gwarancja. Gdy pozycja nie zdąży się
                // ściągnąć na czas, główna pętla i tak poczeka pełne 10s
                // jako właściwe zabezpieczenie — prefetch nigdy nie jest
                // jedynym mechanizmem, tylko dodatkową głową startową.
                _ = await renderDelegate.waitForRender(timeoutSeconds: 3.0)
            }
        }
    }

    /// Silnik renderujący klatki eksportu wideo (dyskretne "zdjęcia" ukrytej
    /// `MKMapView`, klatka po klatce). **31.07.2026 — żywy podgląd już z
    /// niego NIE korzysta** (przeszedł na osobną, natywnie animowaną
    /// `TravelLiveMapView` — naprawa klatkowania w podglądzie, patrz
    /// komentarz tam). Ten silnik zostaje jedynym miejscem produkującym
    /// PLIK wideo — nieogladany w czasie rzeczywistym, więc `captureInterval`
    /// dotyczy tylko kosztu/czasu SAMEGO renderowania, nie wrażenia
    /// płynności na żywo.
    ///
    /// `captureInterval: 1` (31.07.2026, było `3`) — user zauważył realne
    /// "cięcie" w GOTOWYM, zapisanym pliku (2 na 3 klatki bit-identyczne,
    /// bo kamera była "fotografowana" tylko co 3. krok). Świadomy koszt:
    /// ~3x więcej prawdziwych przechwyceń `waitForRender`/`drawHierarchy`
    /// na tę samą długość trasy = wolniejszy zapis.
    ///
    /// `1`→`2` (01.08.2026) — user: "nie może tyle schodzić z zapisem,
    /// musimy znaleźć inną opcję". Realny koszt `captureInterval: 1` razem
    /// z długim limitem czekania (`waitForRender` niżej) OKAZAŁ SIĘ
    /// mnożyć: przy bliskim zoomie z 3D terenem samo RENDEROWANIE (nie
    /// tylko pobieranie kafelków) bywa kosztowne, więc wiele klatek z rzędu
    /// mogło czekać długo. Świadomy, zrównoważony kompromis: co 2. krok
    /// zamiast co 1. (lekkie, prawie niezauważalne "cięcia" zamiast pełnej
    /// płynności) w zamian za wyraźnie krótszy realny czas zapisu.
    ///
    /// `2`→`1` (01.08.2026, ta sama sesja) — user: domyślny motyw zmieniony
    /// na Minimal White (`elevationStyle: .flat`, ZERO siatki terenu 3D,
    /// ZERO zdjęć satelitarnych do zdekodowania). Cały powód wprowadzenia
    /// `captureInterval: 2` (koszt renderowania realistycznego terenu przy
    /// bliskim zoomie) po prostu NIE ISTNIEJE dla płaskiej, wektorowej
    /// mapy — więc pełna płynność (każdy krok to prawdziwe zdjęcie) powinna
    /// być teraz tania. Świadomy kompromis: Satellite (opcjonalny, ręczny
    /// wybór w pickerze) może znowu wydłużyć eksport — akceptowalne, bo to
    /// już nie domyślna ścieżka.
    @MainActor
    static func renderFrames(
        stops: [TripStop], speedMultiplier: Double, mapTheme: MapTheme = .satellite,
        captureInterval: Int? = nil,
        // BUG znaleziony 01.08.2026 (user: "nie widać jak samolot startuje
        // i ląduje, tu wszystko dzieje się za szybko") — prawdziwy rozjazd
        // między silnikami, nie subiektywne wrażenie: żywy podgląd
        // (`TravelLiveMapView`) leci `TravelCinematics.legTotalSeconds` na
        // odcinek — eksport MUSI pokrywać tę samą liczbę sekund wideo (przy
        // 30fps), inaczej rozjeżdża się z tym co user widzi na żywo. 162→261
        // (30fps × `legTotalSeconds`, 01.08.2026: 5.0s oddalenie + 1.35s
        // przelot + 2.35s lądowanie = 8.7s, patrz `TravelCinematics`).
        stepsPerLeg: Int = 261,
        size: CGSize = CGSize(width: 720, height: 1280),
        onFrame: @MainActor (UIImage) async -> Void,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        guard stops.count >= 2 else { throw RenderError.notEnoughStops }

        // Eksperyment 12.08.2026 COFNIĘTY tego samego dnia — próba `1`
        // (pełna częstotliwość dla wszystkich motywów, licząc że
        // `warmupTileCache` wystarczy) na realnym urządzeniu: user "zatrzymało
        // się na 74%... bardzo długo długo to mało powiedziane". Potwierdza
        // podejrzenie z komentarza przy `warmupTileCache`: koszt bliskiego
        // zoomu z realistycznym terenem 3D dla Satellite to głównie LOKALNE
        // renderowanie (GPU), nie sieć — prefetch (atakujący wyłącznie
        // sieciowe czekanie na kafelki) tu nie pomaga. Zostaje `2` dla
        // Satellite jak przed tym eksperymentem — pełna płynność lądu/wody
        // przy tym motywie to osobny, większy temat (`TODO.md`: stylizowana
        // animacja albo świadome obniżenie jakości dla tych segmentów).
        let baseCaptureInterval = captureInterval ?? (mapTheme == .satellite ? 2 : 1)

        // Miniaturki markerów wczytane RAZ na cały render (nie per klatka) —
        // ten sam wzorzec zrównoleglenia co `VideoComposer.resolveSourceURLs`.
        // Puste dla przystanków bez `representativePhotoIdentifier` — zwykła
        // kropka zostaje bez zmian, zero regresji.
        let thumbnails: [UUID: UIImage] = await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for stop in stops {
                guard let identifier = stop.representativePhotoIdentifier else { continue }
                group.addTask { (stop.id, await MediaAssetLoader.markerThumbnail(forAssetLocalIdentifier: identifier)) }
            }
            var result: [UUID: UIImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }

        let fps: Int32 = 30

        // Profil wydajności (01.08.2026) — user (przez zewnętrzną poradę,
        // trafną): zamiast dalej zgadywać liczby dla `captureInterval`/
        // `timeoutSeconds`, zmierz NAPRAWDĘ gdzie ucieka czas. Wypisywane na
        // koniec eksportu (konsola Xcode) — trzy kubełki czasu które można
        // niezależnie zmierzyć stąd: czekanie na kafelki/render MapKit,
        // kompozycja CoreGraphics, i "reszta" (kodowanie wideo + zapis na
        // dysk, mierzone przez czas samego `await onFrame`, patrz `emit`
        // niżej — obejmuje `VideoExporter`/`AVAssetWriter` po stronie
        // wołającego, nie tylko czysto tutejszy kod).
        let profileStart = CFAbsoluteTimeGetCurrent()
        var tileWaitSeconds: Double = 0
        var compositeSeconds: Double = 0
        var encodeSeconds: Double = 0
        // TYMCZASOWE (01.08.2026) — patrz `lastCameraDebug`.
        var cameraDebugLines: [String] = []

        // Margines wokół każdego prawdziwego zdjęcia (12.08.2026, user
        // przysłał film z pociągiem: wyraźna szara dziura w rogu klatki) —
        // "jazda po ponownie użytym zdjęciu" (przesuwanie zamiast zamrożenia,
        // patrz `backgroundShift` niżej) ujawniła realny brzeg: samo zdjęcie
        // nie było większe niż finalna klatka, więc przy większym
        // przesunięciu (dłuższy odcinek między prawdziwymi zdjęciami przy
        // niektórych kombinacjach zoomu/prędkości) część canvasu zostawała
        // bez pokrycia. `captureSize` większy niż `size` daje zapas do
        // przesuwania się PRZED ujawnieniem pustego brzegu — sam
        // `mapView`/`captureWindow` (nie tylko finalna klatka) jest teraz
        // fizycznie większy, więc MapKit renderuje szerszy obszar za jednym
        // razem.
        let captureSize = CGSize(width: size.width * 1.4, height: size.height * 1.4)
        let session = try makeSession(size: captureSize, mapTheme: mapTheme)
        let mapView = session.mapView
        let renderDelegate = session.renderDelegate
        defer { session.captureWindow.isHidden = true }

        // Prefetch kafelków dla CAŁEJ trasy, równolegle z eksportem
        // (12.08.2026, user: "wiemy jak to ma wyglądać i wiemy jak trasa
        // będzie przebiegać i kiedy będą zbliżenia" — po eksperymencie 11.08
        // który tylko zrzedził realne przechwycenia; profil pokazał 85-90%
        // czasu to czekanie na kafelki, więc user chciał zaatakować SAM
        // powód, nie tylko go rzadziej odczuwać). Świadomie NIE poleganie
        // na tym że user obejrzy żywy podgląd przed zapisaniem (choć
        // TEORETYCZNIE powinno to samo w sobie już rozgrzewać wspólny cache
        // MapKit — user słusznie to zauważył) — podgląd akceptuje
        // niedoładowane kafelki (kamera leci dalej, kafelki dociągają się
        // wizualnie w locie), eksport nie może pokazać ani jednej
        // niekompletnej klatki, więc "dotknięcie" pozycji przez podgląd nie
        // gwarantuje że faktycznie zdążyły się w PEŁNI ściągnąć.
        //
        // Zamiast tego: DRUGA, osobna ukryta `MKMapView` (`warmupTileCache`
        // niżej) przechodzi przez DOKŁADNIE te same pozycje kamery co
        // właściwa pętla przechwytywania niżej (ta sama matematyka —
        // `TravelCinematics.frameState`/`easeInOutCubic`/`RouteProvider.
        // cinematicPath` — więc zero zgadywania, appka i tak już z góry
        // wie którędy poleci kamera) — TYLKO PO TO żeby wywołać pobranie
        // kafelków, bez kompozycji/zapisu klatek (dużo tańszy krok niż
        // właściwe przechwycenie), więc naturalnie wyprzedza główną pętlę.
        // Kafelki MapKit są cache'owane systemowo między WSZYSTKIMI
        // `MKMapView` (ten sam fakt wykorzystywany przez
        // `MapTilePrefetcher`) — gdy główna pętla dotrze do tej samej
        // pozycji, w normalnym przypadku znajduje już gotowy kafelek
        // zamiast czekać na sieć. Fire-and-forget: błąd/timeout w
        // prefetchu NIGDY nie przerywa właściwego eksportu, tylko
        // ewentualnie nie zdąży dać przewagi na tym konkretnym odcinku
        // (główna pętla i tak ma własne, pełne czekanie jako zabezpieczenie).
        let warmupTask = Task {
            await warmupTileCache(stops: stops, speedMultiplier: speedMultiplier, mapTheme: mapTheme, captureInterval: baseCaptureInterval, stepsPerLeg: stepsPerLeg, size: size)
        }
        defer { warmupTask.cancel() }

        // "Warm-up" PRZED establishing shotem (01.08.2026, user przez
        // zewnętrzną analizę: "czy możemy dodać etap warm-up przed
        // rozpoczęciem eksportu?") — świeża `MKMapView` z `makeSession` NIGDY
        // wcześniej nie miała ustawionej kamery ani nie renderowała ŻADNEJ
        // pozycji. Bez tego kroku establishing shot (pierwsza właściwa
        // klatka) był jednocześnie PIERWSZYM w ogóle renderem tego widoku —
        // "rozgrzanie" silnika mapy (styl, cache) i czekanie na kafelki
        // KONKRETNEGO bliskiego zoomu działy się w jednym kroku. Żywy
        // podgląd (`TravelLiveMapView.makeUIView`/`start()`) ma ten
        // dwuetapowy wzorzec od dawna (szeroki widok najpierw, bliski zjazd
        // potem) — eksportowi go brakowało. Ten sam mechanizm oczekiwania
        // (`waitForRender`), tylko na SZEROKIM, bezpiecznym widoku, zanim
        // jakakolwiek klatka zostanie faktycznie przechwycona.
        if let firstCoordinate = stops.first?.coordinate {
            mapView.camera = MKMapCamera(lookingAtCenter: firstCoordinate, fromDistance: 1_000_000, pitch: 0, heading: 0)
            _ = await renderDelegate.waitForRender(timeoutSeconds: 10.0)
        }

        /// Ustawia kamerę i CZEKA NA PRAWDZIWY sygnał MapKit
        /// (`mapViewDidFinishRenderingMap`) że kafelki (i siatka terenu przy
        /// `elevation: .realistic`) są gotowe. `timeoutSeconds` to WYŁĄCZNIE
        /// awaryjne zabezpieczenie (np. zerowy internet) — w normalnym
        /// przypadku funkcja wraca od razu po realnym sygnale, nie czeka
        /// pełnego limitu.
        ///
        /// 3.0s→8.0s→25.0s→10.0s (01.08.2026). 25s miało dać twardą
        /// gwarancję zero szarych plam (user: "szarych plam ma NIE BYĆ") —
        /// ale w praktyce, razem z `captureInterval: 1` (wtedy), okazało się
        /// mnożyć: przy bliskim zoomie z 3D terenem samo RENDEROWANIE (nie
        /// tylko sieć) bywa kosztowne, więc wiele klatek z rzędu czekało
        /// długo, a zapis stał się nie do zaakceptowania (user: "nie może
        /// tyle schodzić z zapisem"). 10s to świadomy, zrównoważony
        /// kompromis — razem z `captureInterval: 2` (zamiast `1`) wyraźnie
        /// krótszy realny czas zapisu, wciąż solidny margines ponad zwykły
        /// czas ładowania kafelków (sekundy, nie dziesiątki sekund) na
        /// każdym rozsądnym połączeniu.
        // BUG znaleziony 01.08.2026 (user: "18% i 3min 30s... coś wyraźnie
        // nie działa") — złapane na żywo w konsoli: dla lotów (stały
        // dystans/pochylenie przez CAŁY odcinek, patrz `TravelCinematics.
        // frameState`) TYLKO pierwsze przechwycenie dostaje prawdziwy
        // sygnał `mapViewDidFinishRenderingMap` (0.33s) — każde kolejne
        // czeka PEŁNE 10s i NIGDY nie dostaje sygnału, bo MapKit słusznie
        // uznaje "nic nowego do wyrenderowania" (te same kafelki, ten sam
        // zoom, tylko środek się przesuwa) i po prostu nie wywołuje
        // delegata. ~130 realnych przechwyceń/odcinek × 10s = ponad
        // 20 minut. Naprawa: pomijamy czekanie na sygnał, gdy dystans I
        // pochylenie są IDENTYCZNE jak przy POPRZEDNIM przechwyceniu —
        // wtedy faktycznie nie ma na co czekać (te same kafelki już
        // narysowane), różni się tylko środek (pan), co MapKit renderuje
        // natychmiast/synchronicznie.
        var lastCapturedDistance: CLLocationDistance?
        var lastCapturedPitch: Double?
        var lastUsedFlatElevation: Bool?

        // BUG znaleziony 02.08.2026 (user: pin "London Stansted Airport"
        // konsekwentnie nad morzem, TYLKO w eksporcie, TYLKO dla lotów) —
        // potwierdzone WIZUALNIE (zaznaczenie wyliczonego punktu na
        // faktycznej klatce `f_001.png`): środek kamery konwertuje się
        // BEZBŁĘDNIE (zero odchylenia), ale punkty oddalone o kilkanaście
        // stopni (jak Stansted względem środka trasy Londyn-Teneryfa) lądują
        // grubo obok prawdziwej pozycji. Przyczyna NIE jest w naszym kodzie
        // ani w zapisanych współrzędnych (zweryfikowane wcześniej wprost z
        // bazy) — to `mapView.convert(_:toPointTo:)` licząc pozycję
        // ekranową IGNORUJE krzywiznę globusa (`elevationStyle: .realistic`)
        // przy tak dużym oddaleniu kamery lotu (`ceilingDistance`, prawie 2×
        // promień Ziemi) — poprawne TYLKO dokładnie w środku kadru, błąd
        // rośnie z odległością kątową od środka. Loty jako jedyne używają
        // aż tak szerokiego, stałego kadru, więc jako jedyne to ujawniają.
        // Naprawa: dla lotów mapa przechodzi tymczasowo na PŁASKĄ
        // konfigurację (`elevationStyle: .flat`) — `convert()` jest wtedy
        // matematycznie dokładny (zwykła projekcja 2D, zero krzywizny do
        // pomylenia). Inne środki transportu zostają bez zmian (nadal
        // globus 3D przy motywie Satellite, jeśli wybrany) — dotyczy tylko
        // fragmentów trasy gdzie faktycznie latymy.
        func flatConfiguration() -> MKMapConfiguration {
            switch mapTheme {
            case .satellite:
                return MKHybridMapConfiguration(elevationStyle: .flat)
            case .minimalWhite:
                return mapTheme.mapConfiguration
            }
        }

        func captureBaseImage(center: CLLocationCoordinate2D, distance: CLLocationDistance, pitch: Double, useFlatElevation: Bool) async -> UIImage {
            if lastUsedFlatElevation != useFlatElevation {
                mapView.preferredConfiguration = useFlatElevation ? flatConfiguration() : mapTheme.mapConfiguration
                lastUsedFlatElevation = useFlatElevation
                // Zmiana konfiguracji to nowy render od zera — wymuszamy
                // pełne czekanie na sygnał niżej, ignorując "skip" (stary
                // dystans/pochylenie mogą się przypadkiem zgadzać mimo
                // zupełnie innej konfiguracji mapy).
                lastCapturedDistance = nil
                lastCapturedPitch = nil
            }
            mapView.camera = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: pitch, heading: 0)
            let waitStart = CFAbsoluteTimeGetCurrent()
            // BUG znaleziony 01.08.2026 (user: przesłany film, szary blok w
            // rogu kadru rosnący od ~2400km aż do lądowania) — CAŁKOWITE
            // pomijanie czekania (gdy dystans/pochylenie bez zmian) było za
            // agresywne: kamera lotu wciąż PRZESUWA SIĘ (podąża za
            // samolotem), więc na krawędzi kadru regularnie pojawiają się
            // NOWE, nigdy niezaładowane kafelki — zero czekania = zero
            // szansy żeby zdążyły się doczytać. MapKit i tak NIGDY nie
            // sygnalizuje `mapViewDidFinishRenderingMap` gdy dystans/
            // pochylenie się nie zmieniają (potwierdzone wcześniej: pełen
            // 10s timeout za KAŻDYM razem) — więc krótki, STAŁY zapas czasu
            // (nie czekanie na sygnał, który i tak nie przyjdzie) daje
            // realnemu ładowaniu kafelków szansę, zostając wciąż ~30×
            // szybszym niż oryginalne 10s.
            // Bug znaleziony 03.08.2026 (user: trasa z kilkoma środkami
            // transportu, eksport "37% po kilkunastu minutach") — powyższy
            // fix z 01.08.2026 sprawdzał WYŁĄCZNIE dokładną równość
            // dystansu/pochylenia, co działa tylko dla lotów (tam kamera
            // faktycznie stoi w miejscu przez cały odcinek). Dla
            // samochodu/pociągu/wędrówki/promu kamera PŁYNNIE się zbliża/
            // oddala przez fazy grow/shrink (`TravelCinematics.frameState`)
            // — dystans zmienia się na KAŻDEJ klatce, nigdy dokładnie tak
            // samo, więc dokładna równość nigdy nie była prawdziwa poza
            // krótką fazą cruise. Efekt: te same objawy co przy lotach
            // sprzed fixa — pełne 10s bez sygnału na niemal każdej klatce
            // (~130 przechwyceń/odcinek × do 10s = kilkanaście minut na
            // sam odcinek). Naprawa: tolerancja zamiast dokładnej
            // równości — MapKit i tak nie wysyła sygnału dla drobnych,
            // podpikselowych zmian zoomu (te same kafelki), więc mała
            // zmiana dystansu/pochylenia między klatkami zasługuje na
            // ten sam krótki, stały bufor co brak zmiany w ogóle.
            // Profil z realnego eksportu (03.08.2026, trasa z kilkoma
            // środkami transportu): nawet PO powyższym fixie 90% czasu
            // (771s z 857s, 1412 klatek) to dalej czekanie na kafelki —
            // 1% tolerancji było za ciasne. Kamera lotu/wędrówki/etc.
            // porusza się po krzywej `easeInOutCubic` — w środku fazy
          // grow/shrink dystans zmienia się między kolejnymi z 261 kroków
            // O KILKA PROCENT, nie ułamek procenta, więc prawie żadna
            // klatka nie łapała się w stary, ciasny próg. Kafelki MapKit są
            // skwantowane do dyskretnych poziomów zoomu — kilka procent
            // zmiany dystansu w środku jednego takiego poziomu wciąż
            // oznacza TE SAME kafelki, tylko szybszy, czysto lokalny
            // re-render (bez sieci) — stąd bezpieczne poszerzenie progu.
            let distanceUnchanged = lastCapturedDistance.map { abs($0 - distance) <= max(1, $0 * 0.03) } ?? false
            let pitchUnchanged = lastCapturedPitch.map { abs($0 - pitch) <= 1.5 } ?? false
            let signalled: Bool
            if distanceUnchanged, pitchUnchanged {
                // 300ms→150ms (03.08.2026) — sam ten bufor, pomnożony przez
                // >1000 klatek typowego eksportu, był liczącym się kawałkiem
                // 14-minutowego czasu z profilu. To czysto lokalny
                // re-render (bez sieci, patrz komentarz wyżej), nie
                // potrzebuje aż tyle marginesu.
                try? await Task.sleep(nanoseconds: 150_000_000)
                signalled = true
            } else {
                signalled = await renderDelegate.waitForRender(timeoutSeconds: 10.0)
                // Dodatkowy stały bufor (02.08.2026) — `mapViewDidFinishRenderingMap`
                // potwierdza że MapKit ZACZĄŁ/SKOŃCZYŁ pierwszy przebieg
                // renderowania, NIE że zdalne kafelki (zwłaszcza satelitarne)
                // dla NOWEGO zoomu faktycznie zdążyły się podmienić na
                // ekranie — ten sam mechanizm co 2s bufor po sygnale w
                // `TravelLiveMapView.start()`. UWAGA: to NIE była przyczyna
                // buga z przesuniętym pinem Stansted (ta okazała się być
                // krzywizną globusa w `convert()`, patrz `flatConfiguration`
                // wyżej) — ten bufor zostaje jako niezależne, uczciwe
                // zabezpieczenie przed szarymi/niedoładowanymi kafelkami.
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            lastCapturedDistance = distance
            lastCapturedPitch = pitch
            let waitElapsed = CFAbsoluteTimeGetCurrent() - waitStart
            tileWaitSeconds += waitElapsed
            // TYMCZASOWE (30.07.2026, rozszerzone 01.08.2026) — diagnoza czy
            // MapKit po cichu przycina żądany dystans/pochylenie kamery.
            // User zgłosił (3. raz): kadr TUŻ PO ustawiającym (te same
            // parametry progress=0!) pokazuje dramatycznie szerszy obszar —
            // zapisujemy PIERWSZE kilka wywołań w CAŁOŚCI (nie tylko gdy
            // wykryty rozjazd), żeby zobaczyć naprawdę co się dzieje.
            let actualDistance = mapView.camera.centerCoordinateDistance
            let actualPitch = mapView.camera.pitch
            if cameraDebugLines.count < 6 {
                let mismatch = abs(actualDistance - distance) > distance * 0.05 ? " ⚠️" : ""
                cameraDebugLines.append(
                    "#\(cameraDebugLines.count): req \(Int(distance))m/\(Int(pitch))° → got \(Int(actualDistance))m/\(Int(actualPitch))°\(mismatch)"
                )
            }
            if abs(actualDistance - distance) > distance * 0.05 {
                print("⚠️ TravelMap camera clamp: żądano \(Int(distance))m, MapKit ustawił \(Int(actualDistance))m (pitch żądany \(Int(pitch))°, faktyczny \(Int(actualPitch))°)")
                fflush(stdout)
            }
            // BUG znaleziony 01.08.2026 (user: "apka się wyłączyła") —
            // realny crash log z telefonu (JetsamEvent, nie zwykły crash w
            // kodzie) pokazał proces urósł do ~1.19GB przed zabiciem przez
            // system. Przyczyna: `drawHierarchy` (i cały tymczasowy render
            // tree CALayer pod spodem) alokuje sporo przejściowej pamięci,
            // normalnie zwalnianej przy opróżnieniu autorelease poola —
            // ale odkąd większość przechwyceń jest NATYCHMIASTOWA (patrz
            // fix `lastCapturedDistance`/`lastCapturedPitch` wyżej), pętla
            // przelatuje przez setki iteracji bez naturalnych okazji do
            // opróżnienia poola, więc pamięć rosła bez końca. Jawny
            // `autoreleasepool` wymusza zwolnienie po KAŻDYM przechwyceniu.
            return autoreleasepool {
                // `captureSize`, NIE `size` — `mapView.bounds` jest teraz
                // fizycznie większa niż finalna klatka (margines na
                // przesuwanie, patrz komentarz przy `captureSize` w
                // `renderFrames`).
                let renderer = UIGraphicsImageRenderer(size: captureSize)
                return renderer.image { _ in
                    mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
                }
            }
        }

        /// Kompozycja CoreGraphics (`composite`) zmierzona osobno od
        /// czekania na kafelki — profil (patrz komentarz przy
        /// `profileStart`).
        func measuredComposite(_ body: () -> UIImage) -> UIImage {
            let start = CFAbsoluteTimeGetCurrent()
            let result = autoreleasepool(invoking: body)
            compositeSeconds += CFAbsoluteTimeGetCurrent() - start
            return result
        }

        // Do paska postępu w UI — dokładnie ta sama logika co pętle klatek
        // poniżej, żeby procent był wiarygodny.
        var totalFrameCount = 0
        if let first = stops.first, first.coordinate != nil {
            let departureHold = (stops.count > 1 ? stops[1].transport : .plane) == .plane ? 0.4 : 0.75
            totalFrameCount += Int(Double(fps) * departureHold)
        }
        for legIndex in 0..<(stops.count - 1) {
            guard stops[legIndex].coordinate != nil, stops[legIndex + 1].coordinate != nil else { continue }
            let steps = max(8, Int(Double(stepsPerLeg) / max(1.0, speedMultiplier)))
            let arrivalHold = stops[legIndex + 1].transport == .plane ? 0.4 : 0.75
            totalFrameCount += (steps + 1) + Int(Double(fps) * arrivalHold)
        }

        var emittedFrameCount = 0
        func emit(_ image: UIImage) async {
            // "Kodowanie + zapis" w profilu — dla eksportu `onFrame` to
            // `appendFrame` w `renderVideo` (pixel buffer + `AVAssetWriter`),
            // więc ten czas obejmuje realnie CAŁĄ resztę potoku poza
            // czekaniem na kafelki i kompozycją.
            let encodeStart = CFAbsoluteTimeGetCurrent()
            await onFrame(image)
            encodeSeconds += CFAbsoluteTimeGetCurrent() - encodeStart
            emittedFrameCount += 1
            if totalFrameCount > 0 {
                onProgress?(min(1.0, Double(emittedFrameCount) / Double(totalFrameCount)))
            }
        }

        var completedLegsKm: Double = 0
        var visitedStops: [TripStop] = []

        if let first = stops.first, let firstCoordinate = first.coordinate {
            visitedStops = [first]
            // Kadr startowy skalowany do długości PIERWSZEGO odcinka, nie
            // stałego dystansu — ciągły z pierwszą klatką pętli poniżej.
            // Wstrzymania 0.8s/1.2s → 1.2s/1.8s → 2.0s/2.5s (01.08.2026,
            // user: "filmik działa jak w przyspieszonym tempie i nie widać
            // nawet przystanków", potem "kamera powinna wolniej pokazywać
            // miejsce z którego wylatujemy jak i lądujemy") — jeszcze
            // dłuższy czas na przeczytanie/zobaczenie miejsca startu/mety.
            let firstLegKm = stops.count > 1 ? stops[1].coordinate.map { RouteProvider.straightDistanceKm(from: firstCoordinate, to: $0) } : nil
            let firstTransport = stops.count > 1 ? stops[1].transport : .plane
            let establishingState = TravelCinematics.frameState(progress: 0, legDistanceKm: firstLegKm ?? .infinity, transport: firstTransport)
            // BUG znaleziony 01.08.2026 (user: "punkty startu i lądowania
            // się przemieszczają, nie zostają na mapie") — parytet z
            // `TravelLiveMapView`: dla lotów establishing shot centruje się
            // na środku CAŁEGO odcinka, nie na samym punkcie startu.
            let establishingCenter: CLLocationCoordinate2D
            if firstTransport == .plane, (firstLegKm ?? .infinity) <= TravelCinematics.longFlightFollowThresholdKm,
               stops.count > 1, let secondCoordinate = stops[1].coordinate {
                establishingCenter = RouteProvider.midpoint(from: firstCoordinate, to: secondCoordinate)
            } else {
                establishingCenter = firstCoordinate
            }
            let baseImage = await captureBaseImage(center: establishingCenter, distance: establishingState.cameraDistance, pitch: establishingState.cameraPitch, useFlatElevation: firstTransport == .plane)
            let frame = measuredComposite {
                composite(
                    mapView: mapView, baseImage: baseImage, path: [], progress: 0, transport: nil,
                    bearingDegrees: 0, leanDegrees: 0, iconScale: 1,
                    visitedStops: visitedStops, upcomingStop: nil, cardStop: first, distanceKm: 0, size: size,
                    captureSize: captureSize, thumbnails: thumbnails
                )
            }
            // 1.5s→0.4s DLA LOTÓW (01.08.2026, user: "samolot na lotnisku
            // nie musi być pokazany jak stoi, wystarczy jak leci
            // prawidłowo").
            let departureHold = firstTransport == .plane ? 0.4 : 0.75
            for _ in 0..<Int(Double(fps) * departureHold) { await emit(frame) }
        }

        for legIndex in 0..<(stops.count - 1) {
            let from = stops[legIndex]
            let to = stops[legIndex + 1]
            guard let fromCoordinate = from.coordinate, let toCoordinate = to.coordinate else { continue }

            let result = await RouteProvider.route(from: fromCoordinate, to: toCoordinate, transport: to.transport)
            let path = RouteProvider.cinematicPath(result.path)
            let legDistanceKm = result.distanceKm
            // Parytet z `TravelLiveMapView` — dla krótkich/średnich lotów
            // kamera trzyma stały środek w połowie drogi; powyżej
            // `longFlightFollowThresholdKm` (04.08.2026, patrz stała w
            // `TravelCinematics.swift`) podąża za samolotem jak reszta
            // środków transportu, żeby nie ginął w ogromnym, niezmiennym
            // kadrze przy bardzo długich trasach.
            let legCameraCenter: CLLocationCoordinate2D? = (to.transport == .plane && legDistanceKm <= TravelCinematics.longFlightFollowThresholdKm)
                ? RouteProvider.midpoint(from: fromCoordinate, to: toCoordinate)
                : nil

            // Eksperyment 11.08.2026 ("o jeden krok rzadsze prawdziwe
            // zdjęcie dla lądu/wody") COFNIĘTY 12.08.2026 — user przesłał
            // realny eksport (Londyn→Mielec, samochód): "werdykt nie
            // działa płynnie". Analiza klatka po klatce (diff sąsiednich
            // klatek) POTWIERDZIŁA przyczynę, nie zgadywanie: wzorzec "2
            // klatki zamrożone, potem duży skok" w kółko — dokładnie objaw
            // rzadszego prawdziwego przechwycenia przy kamerze która cały
            // czas PRZESUWA SIĘ (w przeciwieństwie do lotu, gdzie ten sam
            // kadr przez dłużej jest niezauważalny). Zamiast tego
            // kompromisu: `warmupTileCache` (12.08.2026, patrz wyżej)
            // odciąża SAM powód wolnego eksportu (czekanie na kafelki),
            // więc częstotliwość prawdziwych przechwyceń może wrócić do
            // tej samej co dla lotów, bez utraty płynności.
            let effectiveCaptureInterval = baseCaptureInterval

            let steps = max(8, Int(Double(stepsPerLeg) / max(1.0, speedMultiplier)))
            // Realne zdjęcie mapy (przesunięcie kamery + czekanie na MapKit)
            // tylko co `captureInterval` krok, nie na KAŻDY krok — reszta
            // klatek ponownie używa OSTATNIEGO zrobionego zdjęcia jako tła.
            // Dystans/pochylenie liczone TYLKO przy realnym zdjęciu (nie na
            // każdy krok) — inaczej klatki pośrednie pokazywałyby trasę/
            // ikonę ustawioną względem NOWEGO zoomu na tle zrobionym przy
            // STARYM. Skala ikony i przechył zostają per-krok — tanie, samo
            // rysowanie w `composite()`, zero kosztu MapKit. Podgląd na żywo
            // (30.07.2026) prosi o `captureInterval: 1` — dla WATCHED
            // animacji "kamera zamrożona przez 2 klatki, potem skok" jest
            // widoczna jako charakterystyczne "przeskakiwanie" (user: "nie da
            // się oglądać, przeskakuje"), podczas gdy w eksporcie (odtwarzanym
            // ze stałym fps, nikt nie ogląda w czasie rzeczywistym renderowania)
            // ten sam kompromis jest niezauważalny.
            var lastAnimatedPoint = fromCoordinate
            var cachedBaseImage: UIImage?
            var previousHeading: Double?
            var smoothedLean: Double = 0
            for step in 0...steps {
                // Bezpiecznik pamięci (01.08.2026, patrz `autoreleasepool` w
                // `captureBaseImage`) — teraz kiedy dystans/pochylenie
                // kamery się nie zmienia (loty), pętla potrafi przelecieć
                // setki kroków bez ŻADNEGO prawdziwego zawieszenia (`await`),
                // więc systemowi brakuje okazji nadążyć za sprzątaniem. Co
                // 20 kroków oddajemy jawnie kontrolę — tani, gwarantowany
                // punkt zawieszenia niezależny od tego czy dany krok robi
                // realne przechwycenie.
                if step % 20 == 0 { await Task.yield() }
                // Krzywa prędkości pojazdu — parytet z żywym podglądem
                // (`TravelLiveMapView`/`TravelMapboxLiveView`): `progress`
                // przez `easeInOutCubic`, miękki start/koniec zamiast stałej
                // prędkości.
                let rawProgress = Double(step) / Double(steps)
                let progress = TravelCinematics.easeInOutCubic(rawProgress)
                // Interpolacja MIĘDZY sąsiednimi punktami ścieżki (12.08.2026)
                // zamiast zaokrąglania w dół do najbliższego — patrz pełne
                // uzasadnienie przy `RouteProvider.interpolate`. Bez tego
                // pojazd zamierał w miejscu tuż przed przyjazdem, gdzie
                // `easeInOutCubic` spłaszcza się najmocniej.
                let rawIndex = Double(path.count - 1) * progress
                let pointIndex = Int(rawIndex)
                let indexFraction = rawIndex - Double(pointIndex)
                let nextIndex = min(path.count - 1, pointIndex + 1)
                let previousIndex = max(0, pointIndex - 1)
                let point = RouteProvider.interpolate(from: path[pointIndex], to: path[nextIndex], fraction: indexFraction)
                lastAnimatedPoint = point
                // Ślad trasy sięga do PŁYNNEJ pozycji (nie tylko zaokrąglonego
                // indeksu) — inaczej czubek linii miałby ten sam problem co
                // sam pojazd.
                let revealedPath = Array(path[0...pointIndex]) + [point]
                let heading = RouteProvider.bearing(from: path[previousIndex], to: point)
                let rawLean = TravelCinematics.rawLeanDegrees(previousHeading: previousHeading, currentHeading: heading)
                smoothedLean = TravelCinematics.smoothedLean(previous: smoothedLean, target: rawLean)
                previousHeading = heading

                // Bug znaleziony 03.08.2026 (trasa z kilkoma środkami
                // transportu, profil: 85-90% czasu eksportu to czekanie na
                // kafelki) — próba (crossfade między rzadszymi prawdziwymi
                // zdjęciami) COFNIĘTA: kamera dla samochodu/pociągu/
                // wędrówki/promu nie tylko zoomuje, ale i PRZESUWA SIĘ
                // (podąża za pojazdem) — przenikanie dwóch zdjęć z różnym
                // środkiem kadru dawało upiornie PODWOJONE etykiety miast/
                // dróg (potwierdzone wizualnie, user: "zdecydowanie nie").
                // Zostaje bezpieczna wersja: szersza tolerancja (03.08.2026,
                // niżej w `captureBaseImage`) + krótszy bufor, bez żadnego
                // blendowania obrazów.
                let needsFreshCapture = cachedBaseImage == nil || step % effectiveCaptureInterval == 0 || step == steps
                if needsFreshCapture {
                    let frameState = TravelCinematics.frameState(progress: progress, legDistanceKm: legDistanceKm, transport: to.transport)
                    cachedBaseImage = await captureBaseImage(center: legCameraCenter ?? point, distance: frameState.cameraDistance, pitch: frameState.cameraPitch, useFlatElevation: to.transport == .plane)
                }
                guard let baseImage = cachedBaseImage else { continue }
                let iconScale = TravelCinematics.iconScale(progress: progress)
                // "Jazda po ponownie użytym zdjęciu" (12.08.2026, user: "czy
                // da się połączyć płynnie kilka zdjęć z całej trasy, żeby
                // samochód sobie po tym przejeżdżał płynnie?") — INNE
                // podejście niż odrzucone 03.08.2026 przenikanie dwóch
                // zdjęć (to dawało PODWOJONE etykiety, bo blendowało DWA
                // różne zdjęcia naraz). Tu jest cały czas TYLKO JEDNO
                // zdjęcie — po prostu przesuwane o dokładnie tyle, o ile
                // rzeczywiście przejechaliśmy od ostatniego prawdziwego
                // zdjęcia. `mapView.camera` zostaje NIETKNIĘTA między
                // prawdziwymi zdjęciami (jak dotąd), więc `convert()` wciąż
                // odzwierciedla STARĄ projekcję — różnica między tym gdzie
                // AKTUALNY środek kamery (`legCameraCenter ?? point`) by się
                // teraz zrzutował a środkiem canvasu to dokładnie potrzebne
                // przesunięcie tła. Zero kosztu MapKit — czyste
                // CoreGraphics w `composite()`.
                let cameraCenterCoordinate = legCameraCenter ?? point
                let projectedCameraCenter = mapView.convert(cameraCenterCoordinate, toPointTo: mapView)
                // Środek `mapView` to `captureSize / 2`, NIE `size / 2`
                // (12.08.2026) — `mapView.bounds` jest teraz fizycznie
                // większa niż finalna klatka (margines na przesuwanie).
                let backgroundShift = CGPoint(x: projectedCameraCenter.x - captureSize.width / 2, y: projectedCameraCenter.y - captureSize.height / 2)
                let frame = measuredComposite {
                    composite(
                        mapView: mapView, baseImage: baseImage, path: revealedPath, progress: progress, transport: to.transport,
                        bearingDegrees: heading, leanDegrees: smoothedLean, iconScale: iconScale,
                        visitedStops: visitedStops, upcomingStop: to, cardStop: nil,
                        distanceKm: completedLegsKm + legDistanceKm * progress, size: size,
                        captureSize: captureSize, thumbnails: thumbnails, backgroundShift: backgroundShift
                    )
                }
                await emit(frame)
            }

            completedLegsKm += legDistanceKm
            visitedStops.append(to)
            // Kamera zostaje na współrzędnej OSTATNIEJ animowanej klatki, nie
            // dokładnym `toCoordinate` — unika mikro-skoku przy lądowaniu.
            let arrivalState = TravelCinematics.frameState(progress: 1.0, legDistanceKm: legDistanceKm, transport: to.transport)
            let arrivalBaseImage = await captureBaseImage(center: legCameraCenter ?? lastAnimatedPoint, distance: arrivalState.cameraDistance, pitch: arrivalState.cameraPitch, useFlatElevation: to.transport == .plane)
            let arrivalFrame = measuredComposite {
                // `bearingDegrees`/`leanDegrees`/`iconScale` nie mają tu
                // znaczenia — `composite()` nie rysuje ikony przy
                // `progress == 1.0` (pojazd już "dojechał").
                composite(
                    mapView: mapView, baseImage: arrivalBaseImage, path: path, progress: 1.0, transport: to.transport,
                    bearingDegrees: 0, leanDegrees: 0, iconScale: 1,
                    visitedStops: visitedStops, upcomingStop: nil, cardStop: to, distanceKm: completedLegsKm, size: size,
                    captureSize: captureSize, thumbnails: thumbnails
                )
            }
            // 1.5s→0.4s DLA LOTÓW (01.08.2026) — ten sam powód co postój
            // przed startem wyżej.
            let arrivalHold = to.transport == .plane ? 0.4 : 0.75
            for _ in 0..<Int(Double(fps) * arrivalHold) { await emit(arrivalFrame) }
        }

        printProfile(
            frameCount: emittedFrameCount, tileWaitSeconds: tileWaitSeconds,
            compositeSeconds: compositeSeconds, encodeSeconds: encodeSeconds,
            totalSeconds: CFAbsoluteTimeGetCurrent() - profileStart
        )
        lastCameraDebug = cameraDebugLines.joined(separator: "\n")
    }

    /// Wypisuje profil (konsola Xcode) — zamiast dalej zgadywać liczby dla
    /// `captureInterval`/`timeoutSeconds`, widać NAPRAWDĘ gdzie ucieka czas
    /// przy realnym eksporcie na urządzeniu.
    @MainActor
    private static func printProfile(
        frameCount: Int, tileWaitSeconds: Double, compositeSeconds: Double,
        encodeSeconds: Double, totalSeconds: Double
    ) {
        guard frameCount > 0, totalSeconds > 0 else { return }
        let avgFrameMs = (totalSeconds / Double(frameCount)) * 1000
        let tilePct = (tileWaitSeconds / totalSeconds) * 100
        let compositePct = (compositeSeconds / totalSeconds) * 100
        let encodePct = (encodeSeconds / totalSeconds) * 100
        let otherPct = max(0, 100 - tilePct - compositePct - encodePct)
        let summary = """
        Frames: \(frameCount) · Avg: \(String(format: "%.0f", avgFrameMs)) ms
        Tiles/render: \(String(format: "%.0f", tilePct))% · Compositing: \(String(format: "%.0f", compositePct))%
        Encoding+disk: \(String(format: "%.0f", encodePct))% · Other: \(String(format: "%.0f", otherPct))%
        Total: \(String(format: "%.1f", totalSeconds)) s
        """
        print("📊 Travel Export Profile\n\(summary)")
        fflush(stdout)
        lastProfileSummary = summary
    }

    static func renderAndSave(
        stops: [TripStop], speedMultiplier: Double, mapTheme: MapTheme = .satellite,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        let url = try await renderVideo(stops: stops, speedMultiplier: speedMultiplier, mapTheme: mapTheme, onProgress: onProgress)
        try await saveToLibrary(url)
    }

    /// `PHPhotosErrorDomain` (np. `operationInterrupted`, kod 3301) potrafi
    /// przerwać sam zapis do biblioteki nawet gdy plik wideo już poprawnie
    /// wyrenderowany — to znany, udokumentowany hiccup systemowego frameworka
    /// Zdjęć (potwierdzone też u innych appek, np. Halide), nie coś do
    /// naprawienia w naszym kodzie. User: appka ma reagować solidnie mimo to
    /// — więc automatyczne ponowienie SAMEGO zapisu (plik już istnieje na
    /// dysku, nie trzeba renderować od nowa) zanim pokażemy błąd userowi.
    private static func saveToLibrary(_ url: URL, attempt: Int = 1, maxAttempts: Int = 3) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            guard attempt < maxAttempts else { throw error }
            try? await Task.sleep(nanoseconds: 500_000_000)
            try await saveToLibrary(url, attempt: attempt + 1, maxAttempts: maxAttempts)
        }
    }

    @MainActor
    static func renderVideo(
        stops: [TripStop], speedMultiplier: Double, mapTheme: MapTheme = .satellite,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        // 1080×1920 → 720×1280 (01.08.2026, user: "może 640/480 pozwoli na
        // szybsze zapisywanie" — dokładnie 640×480 zmieniłoby proporcje na
        // poziome 4:3, psując cały układ kart/ikon dobrany pod pionowy ekran
        // 9:16). Ten sam kierunek (mniej pikseli = szybsza kompozycja/
        // kodowanie), ale z ZACHOWANIEM proporcji 9:16 — 44% mniej pikseli
        // niż 1080×1920 przy identycznym wyglądzie układu (wszystko skaluje
        // się przez `size.width / 1080`, patrz `canonicalScale`/`composite`).
        let size = CGSize(width: 720, height: 1280)
        let fps: Int32 = 30

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: pixelAttrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var frameIndex: Int64 = 0
        func appendFrame(_ image: UIImage) async {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            autoreleasepool {
                guard let pool = adaptor.pixelBufferPool else { return }
                var pixelBufferOut: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
                guard status == kCVReturnSuccess, let buffer = pixelBufferOut else { return }
                draw(image, into: buffer, size: size)
                adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps))
                frameIndex += 1
            }
        }

        try await renderFrames(
            stops: stops, speedMultiplier: speedMultiplier, mapTheme: mapTheme,
            size: size,
            onFrame: { image in await appendFrame(image) },
            onProgress: onProgress
        )

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status == .failed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "unknown write error")
        }
        return outputURL
    }

    private static func composite(
        mapView: MKMapView,
        baseImage: UIImage,
        path: [CLLocationCoordinate2D],
        progress: Double,
        transport: TransportMode?,
        bearingDegrees: Double,
        leanDegrees: Double,
        iconScale: Double,
        visitedStops: [TripStop],
        upcomingStop: TripStop?,
        cardStop: TripStop?,
        distanceKm: Double,
        size: CGSize,
        // Rzeczywisty rozmiar `baseImage` (12.08.2026, zwykle WIĘKSZY niż
        // `size` — margines na przesuwanie, patrz `captureSize` w
        // `renderFrames`). Zawsze wymagany, nie ma sensownej wartości
        // domyślnej — `baseImage` po zmianie z 12.08.2026 NIGDY nie jest
        // dokładnie `size`.
        captureSize: CGSize,
        thumbnails: [UUID: UIImage] = [:],
        // Patrz komentarz przy użyciu w ciele funkcji + przy wywołaniu z
        // głównej pętli (`backgroundShift` w `renderFrames`, 12.08.2026).
        backgroundShift: CGPoint = .zero
    ) -> UIImage {
        // Skala względem KANONICZNEGO rozmiaru eksportu (1080 pt szerokości)
        // — podgląd (30.07.2026) przechwytuje w dużo mniejszym `size` dla
        // wydajności (mniej kafelków MapKit do wyrenderowania), ale sam
        // obraz jest potem rozciągany na pełny ekran. Bez tego skalowania
        // czcionki/odstępy/rozmiary ikon narysowane w STAŁYCH punktach
        // (dobranych pod 1080 pt) zajmowałyby dużo WIĘKSZY procent małego
        // canvasu, a potem urosłyby jeszcze bardziej przy rozciąganiu na
        // ekran — user: "wszystko bardzo duże". Eksport (size.width == 1080)
        // dostaje `scale == 1`, zero zmiany zachowania.
        let scale = size.width / 1080
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Domyślna jakość interpolacji `CGContext` potrafi być zauważalnie
            // gorsza niż to, co za darmo dawał SwiftUI `Image(...).resizable()`
            // w starym podglądzie — źródłowe ikony pojazdów są małe (np.
            // `car_top.png` to zaledwie 98×166 px), więc przy skalowaniu w dół
            // do ~50pt bez jawnie wysokiej jakości wygląda blokowo/kanciasto
            // (user: "samochód wygląda jak kwadrat"). Ustawione raz, na cały
            // kontekst klatki — obejmuje też bazowy obraz mapy i etykiety.
            ctx.cgContext.interpolationQuality = .high

            // Przesunięcie "jazdy po ponownie użytym zdjęciu" (12.08.2026,
            // user: "czy da się połączyć płynnie kilka zdjęć z całej trasy,
            // żeby samochód sobie po tym przejeżdżał płynnie?") — patrz pełne
            // uzasadnienie przy `backgroundShift` w wywołaniu z głównej
            // pętli. Zamiast rysować `baseImage` (i wszystko co liczy się
            // względem TEJ SAMEJ, nieruchomej projekcji `mapView`) dokładnie
            // w (0,0), przesuwamy WSZYSTKO co jest w przestrzeni świata o
            // `-backgroundShift` — tak jakby kamera NAPRAWDĘ była wycentrowana
            // na aktualnej (płynnej) pozycji, mimo że prawdziwe zdjęcie
            // mapy jest starsze. `marginOffset` centruje dodatkowo WIĘKSZE
            // (`captureSize`) zdjęcie względem mniejszego finalnego canvasu
            // (`size`) — bez tego samo wycentrowanie większego zdjęcia by się
            // rozjechało, zanim jeszcze doliczy się realne przesunięcie.
            // Odznaka dystansu i karta przyjazdu ŚWIADOMIE POZA tym blokiem
            // — to elementy przyklejone do ekranu, nie do świata, nie
            // powinny "jechać" razem z mapą.
            let marginOffset = CGPoint(x: (size.width - captureSize.width) / 2, y: (size.height - captureSize.height) / 2)
            let worldOffset = CGPoint(x: marginOffset.x - backgroundShift.x, y: marginOffset.y - backgroundShift.y)
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: worldOffset.x, y: worldOffset.y)
            baseImage.draw(in: CGRect(origin: .zero, size: captureSize))
            ctx.cgContext.restoreGState()

            drawDistanceBadge(distanceKm, in: ctx.cgContext, canvasSize: size, scale: scale)
            drawWatermark(in: ctx.cgContext, canvasSize: size, scale: scale)

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: worldOffset.x, y: worldOffset.y)

            for stop in visitedStops {
                if let coordinate = stop.coordinate {
                    let point = mapView.convert(coordinate, toPointTo: mapView)
                    drawGlobeCityLabel(stop, at: point, in: ctx.cgContext, dimmed: false, scale: scale, thumbnail: thumbnails[stop.id])
                }
            }
            if let upcomingStop, let coordinate = upcomingStop.coordinate {
                let point = mapView.convert(coordinate, toPointTo: mapView)
                drawGlobeCityLabel(upcomingStop, at: point, in: ctx.cgContext, dimmed: true, scale: scale, thumbnail: thumbnails[upcomingStop.id])
            }

            if path.count > 1 {
                let points = path.map { mapView.convert($0, toPointTo: mapView) }

                let linePath = CGMutablePath()
                linePath.addLines(between: points)
                ctx.cgContext.addPath(linePath)
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                let lineTransport = transport ?? .car
                ctx.cgContext.setLineWidth(RouteProvider.lineWidth(for: lineTransport) * 1.5 * scale)
                ctx.cgContext.setLineDash(phase: 0, lengths: RouteProvider.lineDashPattern(for: lineTransport).map { CGFloat($0) * scale })
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineJoin(.round)
                ctx.cgContext.strokePath()

                if let transport, progress < 1.0, points.count > 1 {
                    let currentPoint = points.last!
                    ctx.cgContext.saveGState()
                    ctx.cgContext.translateBy(x: currentPoint.x, y: currentPoint.y)
                    ctx.cgContext.setShadow(offset: .zero, blur: 6 * scale, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                    if transport == .hiking {
                        // Emoji zamiast pseudo-3D grafiki — patrz
                        // `TravelMap.swift` (HISTORIA) po uzasadnienie.
                        let iconSize = 32 * iconScale * scale
                        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: iconSize)]
                        let text = transport.emoji as NSString
                        let textSize = text.size(withAttributes: attrs)
                        text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attrs)
                    } else {
                        let resolved = VehicleIconSet.resolve(transport: transport, bearing: bearingDegrees)
                        // BEZ negacji — `leanDegrees` (przechył na zakręcie,
                        // `TravelCinematics`) doklejony do namiaru, NIGDY nie
                        // zasila samego `bearing` przekazanego do `resolve`
                        // wyżej (zmieniłoby wybór assetu left/right/top w
                        // połowie zakrętu).
                        ctx.cgContext.rotate(by: (resolved.rotationDegrees + leanDegrees) * .pi / 180)
                        if let vehicleImage = UIImage(named: resolved.assetName) {
                            // BUG znaleziony 31.07.2026 w żywym podglądzie
                            // (`TravelLiveMapView`, user: "sprawdź jaki
                            // kształt ma samochód" — 98×166px, wydłużony, NIE
                            // kwadrat) — wymuszanie `width == height` ściskało
                            // naturalnie podłużne assety (samochód/pociąg/bok
                            // łodzi) w kwadrat. Ten sam błąd był i tutaj,
                            // mniej zauważalny przy mniejszym rozmiarze w
                            // eksporcie — poprawione identycznie, żeby
                            // podgląd i eksport znowu wyglądały tak samo.
                            let iconHeight = 56 * iconScale * scale
                            let aspect = vehicleImage.size.height > 0 ? vehicleImage.size.width / vehicleImage.size.height : 1
                            let iconWidth = iconHeight * aspect
                            vehicleImage.draw(in: CGRect(x: -iconWidth / 2, y: -iconHeight / 2, width: iconWidth, height: iconHeight))
                        }
                    }
                    ctx.cgContext.restoreGState()
                }
            }

            ctx.cgContext.restoreGState()

            if let cardStop {
                drawCard(for: cardStop, in: ctx.cgContext, canvasSize: size, scale: scale)
            }
        }
    }

    private static func drawDistanceBadge(_ km: Double, in context: CGContext, canvasSize: CGSize, scale: CGFloat) {
        let text = String(format: "%.0f km", km)
        let font = UIFont.systemFont(ofSize: 26 * scale, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let padding: CGFloat = 14 * scale
        let badgeWidth = textSize.width + padding * 2
        let badgeHeight = textSize.height + padding
        let badgeRect = CGRect(x: canvasSize.width - badgeWidth - 24 * scale, y: 50 * scale, width: badgeWidth, height: badgeHeight)

        context.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
        context.addPath(UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeHeight / 2).cgPath)
        context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: badgeRect.minX + padding, y: badgeRect.minY + padding / 2),
            withAttributes: attrs
        )
    }

    /// Etykieta miasta przypięta do punktu na mapie — flaga, nazwa wielkimi
    /// literami, kraj, ciemne tło, mały niebieski punkt DOKŁADNIE na
    /// współrzędnej (30.07.2026 — wcześniej przesunięty o padding wewnątrz
    /// karty, niewidoczne przy starym, dalekim zoomie, ale rażące przy
    /// nowym, bliższym — user: "kropka nie jest w miejscu gdzie zatrzymuje
    /// się dany środek transportu"). `dimmed` = cel jeszcze nieosiągnięty.
    /// 26.08.2026 — Free/Premium branding (`Pricing.md`): znak wodny na
    /// segmencie animowanej mapy, na razie widoczny dla WSZYSTKICH
    /// (świadoma, tymczasowa decyzja fazy wzrostu — "trzeba to reklamować,
    /// usunie się jak będzie więcej userów", nie stałe rozróżnienie
    /// Free/Premium na starcie). Prawdziwy watermark (delikatny, z cieniem
    /// zamiast twardej plakietki jak `drawDistanceBadge`) — ma wtapiać się
    /// w mapę, nie wyglądać jak element interfejsu. Lewy dolny róg — prawy
    /// górny zajęty przez odznakę dystansu.
    private static func drawWatermark(in context: CGContext, canvasSize: CGSize, scale: CGFloat) {
        let text = "PMemories"
        let font = UIFont.systemFont(ofSize: 22 * scale, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: 24 * scale, y: canvasSize.height - textSize.height - 40 * scale)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1 * scale), blur: 4 * scale, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawGlobeCityLabel(_ stop: TripStop, at point: CGPoint, in context: CGContext, dimmed: Bool, scale: CGFloat, thumbnail: UIImage? = nil) {
        let alpha: CGFloat = dimmed ? 0.6 : 1.0
        let flag = CityGeocoder.flagEmoji(countryCode: stop.countryCode)
        let city = stop.cityName.uppercased()
        let country = (stop.country ?? "").uppercased()

        // Rozmiary 15/12/9 → 24/20/15 (31.07.2026, user: "nazwy miast są
        // bardzo małe, praktycznie niewidoczne") — 12pt na kanwie 1080px
        // szerokości to realnie mikroskopijny tekst po wyświetleniu.
        let flagFont = UIFont.systemFont(ofSize: 24 * scale)
        let cityFont = UIFont.systemFont(ofSize: 20 * scale, weight: .bold)
        let countryFont = UIFont.systemFont(ofSize: 15 * scale, weight: .medium)
        let cityAttrs: [NSAttributedString.Key: Any] = [.font: cityFont, .foregroundColor: UIColor.white.withAlphaComponent(alpha)]
        let countryAttrs: [NSAttributedString.Key: Any] = [.font: countryFont, .foregroundColor: UIColor.white.withAlphaComponent(alpha * 0.7)]
        let flagAttrs: [NSAttributedString.Key: Any] = [.font: flagFont]

        let citySize = (city as NSString).size(withAttributes: cityAttrs)
        let countrySize = country.isEmpty ? .zero : (country as NSString).size(withAttributes: countryAttrs)
        let flagSize = (flag as NSString).size(withAttributes: flagAttrs)

        // Miniaturka zdjęcia (30.07.2026) zastępuje zwykłą kropkę gdy dostępna
        // — wyraźnie większa (żeby faktycznie było widać zdjęcie), reszta
        // układu (`dotCardGap`/`boxRect`) skaluje się z nią automatycznie.
        let dotSize: CGFloat = thumbnail != nil ? 26 * scale : 8 * scale
        let dotCardGap: CGFloat = 6 * scale
        let padding: CGFloat = 9 * scale
        let textBlockWidth = max(citySize.width, countrySize.width, flagSize.width)
        let textBlockHeight = flagSize.height + citySize.height + (country.isEmpty ? 0 : countrySize.height) + 2 * scale
        let boxWidth = textBlockWidth + padding * 2
        let boxHeight = textBlockHeight + padding * 2

        let dotRect = CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)
        let boxRect = CGRect(x: point.x + dotSize / 2 + dotCardGap, y: point.y - boxHeight / 2, width: boxWidth, height: boxHeight)

        context.setFillColor(UIColor.black.withAlphaComponent(0.55 * alpha).cgColor)
        context.addPath(UIBezierPath(roundedRect: boxRect, cornerRadius: 10 * scale).cgPath)
        context.fillPath()

        if let thumbnail {
            context.saveGState()
            context.addPath(UIBezierPath(ovalIn: dotRect).cgPath)
            context.clip()
            thumbnail.draw(in: dotRect, blendMode: .normal, alpha: alpha)
            context.restoreGState()
            context.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(1.5 * scale)
            context.addPath(UIBezierPath(ovalIn: dotRect.insetBy(dx: 0.75 * scale, dy: 0.75 * scale)).cgPath)
            context.strokePath()
        } else {
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(alpha).cgColor)
            context.addPath(UIBezierPath(ovalIn: dotRect).cgPath)
            context.fillPath()
        }

        var textY = boxRect.minY + padding
        let textX = boxRect.minX + padding
        (flag as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: flagAttrs)
        textY += flagSize.height
        (city as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: cityAttrs)
        textY += citySize.height
        if !country.isEmpty {
            (country as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: countryAttrs)
        }
    }

    private static func drawCard(for stop: TripStop, in context: CGContext, canvasSize: CGSize, scale: CGFloat) {
        let cardRect = CGRect(x: 24 * scale, y: canvasSize.height - 220 * scale, width: canvasSize.width - 48 * scale, height: 100 * scale)
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 20 * scale)
        context.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()

        let title = "\(CityGeocoder.flagEmoji(countryCode: stop.countryCode))  \(stop.cityName.uppercased())"
        (title as NSString).draw(
            at: CGPoint(x: cardRect.minX + 20 * scale, y: cardRect.minY + 14 * scale),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32 * scale), .foregroundColor: UIColor.white]
        )
        (subtitle(for: stop) as NSString).draw(
            at: CGPoint(x: cardRect.minX + 20 * scale, y: cardRect.minY + 56 * scale),
            withAttributes: [.font: UIFont.systemFont(ofSize: 22 * scale), .foregroundColor: UIColor.white.withAlphaComponent(0.8)]
        )
    }

    /// Kraj + data pobytu (jeśli ustawiona) w jednej linii, żeby nie zmieniać
    /// wysokości karty — sam dopisek daty na końcu istniejącego wiersza.
    private static func subtitle(for stop: TripStop) -> String {
        guard let arrivalDate = stop.arrivalDate else { return stop.country ?? "" }
        let formatted = dateFormatter.string(from: arrivalDate)
        guard let country = stop.country, !country.isEmpty else { return formatted }
        return "\(country)  •  \(formatted)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    /// Rysuje klatkę w bufor pobrany z puli adaptora (nie `CVPixelBufferCreate`
    /// od zera co klatkę — realna przyczyna zabijania appki w trakcie
    /// dłuższego eksportu, patrz HISTORIA.md).
    private static func draw(_ image: UIImage, into buffer: CVPixelBuffer, size: CGSize) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        guard let cgImage = image.cgImage else { return }
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
    }
}

/// Sygnalizuje kiedy `MKMapView` skończyła renderować bieżącą klatkę mapy —
/// zamiast zgadywać czas oczekiwania, czekamy na oficjalny sygnał MapKit.
/// `timeoutSeconds` w `waitForRender` to WYŁĄCZNIE zabezpieczenie na wypadek
/// gdyby delegat nigdy się nie wywołał — ma być na tyle długi, żeby w
/// normalnych warunkach realny sygnał zawsze zdążył przyjść pierwszy.
@MainActor
private final class MapRenderDelegate: NSObject, MKMapViewDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    /// Czeka na sygnał `mapViewDidFinishRenderingMap`, z górnym limitem
    /// `timeoutSeconds` na wypadek gdyby MapKit go nie wywołał. Zwraca
    /// `true` gdy zadecydował prawdziwy sygnał MapKit, `false` gdy
    /// zadziałał timeout.
    func waitForRender(timeoutSeconds: Double) async -> Bool {
        await withCheckedContinuation { cont in
            continuation = cont
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self.resume(viaSignal: false)
            }
        }
    }

    nonisolated func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        guard fullyRendered else { return }
        Task { @MainActor in self.resume(viaSignal: true) }
    }

    private func resume(viaSignal: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: viaSignal)
    }
}
