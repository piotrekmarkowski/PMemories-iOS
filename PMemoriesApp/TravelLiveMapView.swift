import SwiftUI
import MapKit

/// Żywy, PŁYNNIE animowany podgląd trasy — naprawia znane klatkowanie
/// (`Travel.md`/`TODO.md`) opisane 31.07.2026. Poprzednia wersja
/// (`TravelMapAnimationView` przed tą zmianą) dzieliła DOSŁOWNIE jeden
/// silnik z eksportem wideo (`TravelMapVideoRenderer.renderFrames`) —
/// gwarancja 100% zgodności wyglądu, ale kamera poruszała się dyskretnymi
/// skokami (zdjęcie mapy → czekanie na MapKit → kolejne zdjęcie), bo eksport
/// i tak nie musi być płynny w czasie rzeczywistym.
///
/// Ten widok NIE dotyka eksportu (`TravelMapVideoRenderer.swift` bez zmian)
/// — to osobny silnik, TYLKO dla żywego podglądu, prawdziwa widoczna
/// `MKMapView` z natywną animacją kamery (`setCamera`/`UIView.animate`).
/// Zero ryzyka rozjazdu z eksportem mimo dwóch implementacji: oba silniki
/// nadal karmią się TYMI SAMYMI wartościami (`TravelCinematics.frameState`,
/// `RouteProvider.route`/`cinematicPath`/`lineWidth`/`lineDashPattern`,
/// `VehicleIconSet.resolve`) — pilnujemy zgodności WARTOŚCI wjeżdżających
/// do kamery/trasy/ikony, nie identyczności TECHNIKI renderowania (ten sam
/// wzorzec co uzasadnienie w `TravelMapVideoRenderer.swift` dla V2).
///
/// Odznaka dystansu zostaje w SwiftUI (`TravelMapAnimationView`, prosty,
/// NIE geo-zakotwiczony element). Etykieta przystanku (31.07.2026, user:
/// "zamiast chmurki na dole... flaga gdzie flaga mówi o nazwie a trzon
/// pokazuje punkt") to prawdziwa `MKAnnotationView` — chorągiewka z nazwą
/// osadzona na trzonku kończącym się DOKŁADNIE na współrzędnej przystanku
/// (`StopFlagAnnotation`), zamiast karty przyklejonej na sztywno do dołu
/// ekranu.
struct TravelLiveMapView: UIViewRepresentable {
    let stops: [TripStop]
    var speedMultiplier: Double = 1.0
    var mapTheme: MapTheme = .satellite
    /// Zmiana wartości (np. UUID) restartuje animację od zera — używane
    /// przez przycisk "Odtwórz ponownie" w `TravelMapAnimationView`.
    let runToken: AnyHashable
    /// `true` podczas `TravelMapVideoRenderer.renderAndSave` — REALNY bug
    /// znaleziony 31.07.2026 (user: "strasznie długo zapisuje"): eksport
    /// używa WŁASNEJ, ukrytej `MKMapView` (`TravelMapVideoRenderer.
    /// makeSession`) — żywy podgląd animujący się w tle NIEZALEŻNIE przez
    /// cały czas zapisu walczył o te same zasoby MapKit (siatka terenu/
    /// kafelki satelitarne), wyraźnie spowalniając `waitForRender` w
    /// eksporcie. Podgląd zatrzymuje animację na czas zapisu — user i tak
    /// patrzy wtedy na pasek postępu, nie na mapę.
    var isPaused: Bool = false

    var onDistanceUpdate: (Double) -> Void = { _ in }
    var onLightingUpdate: (LightingCondition, LightingCondition, Double) -> Void = { _, _, _ in }
    var onFinished: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.preferredConfiguration = mapTheme.mapConfiguration
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 20_000_000)
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = mapTheme.pointOfInterestFilter
        mapView.delegate = context.coordinator
        // Świeża `MKMapView` bez ustawionej kamery pokazuje pusty/szary
        // ekran, dopóki coś jej nie każe wyrenderować konkretnego miejsca —
        // REALNY BUG znaleziony 31.07.2026 (user: "wydaje mi się że import
        // mapy nie był na tyle szybki", zrzut ekranu pustego szarego kadru
        // tuż po bardzo bliskim kadrze startowym). Ustawienie kamery na
        // SZEROKIM, bezpiecznym dystansie OD RAZU (bez animacji, więc bez
        // czekania na klatki) daje MapKitowi coś do wyrenderowania natychmiast
        // — właściwy, bliski kadr startowy (patrz `Coordinator.runAnimation`)
        // i tak dojeżdża do niego animacją zaraz potem.
        if let firstCoordinate = stops.first?.coordinate {
            mapView.camera = MKMapCamera(
                lookingAtCenter: firstCoordinate, fromDistance: TravelCinematics.ceilingDistance,
                pitch: 0, heading: 0
            )
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if isPaused {
            // Bug znaleziony 03.08.2026 (przegląd kodu) — `cancel()` samo w
            // sobie NIE resetowało `lastRunToken`, więc gdy `isPaused` wracał
            // do `false` po zakończeniu zapisu (a `runToken` się nie zmienił
            // — to wciąż ta sama sesja podglądu), strażnik niżej (`!=`) był
            // fałszywy i `start()` nigdy nie wywoływał się ponownie: podgląd
            // zamrażał się NA STAŁE, jeśli user kliknął "Save as Video"
            // zanim animacja skończyła się sama (naturalne zakończenie
            // wywołuje `onFinished()`/pokazuje "Play Again" — ta ścieżka
            // działała, tylko przerwanie w trakcie nie). Czyszczenie tokenu
            // tu odtwarza DOKŁADNIE ten sam mechanizm restartu co przycisk
            // "Play Again" (nowy `runToken` z zewnątrz) — po zapisie
            // animacja zaczyna się od nowa, zamiast zostać zamrożona.
            context.coordinator.cancel()
            context.coordinator.lastRunToken = nil
            return
        }
        guard context.coordinator.lastRunToken != runToken else { return }
        context.coordinator.lastRunToken = runToken
        context.coordinator.start(mapView: mapView, stops: stops, speedMultiplier: speedMultiplier, view: self)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastRunToken: AnyHashable?
        private var task: Task<Void, Never>?
        private var vehicleAnnotation: VehicleAnnotation?
        private var vehicleAnnotationView: MKAnnotationView?
        private var currentRouteOverlay: MKPolyline?
        private var currentRouteRenderer: RevealingPolylineRenderer?
        private var stopFlagAnnotation: StopFlagAnnotation?
        private var stopFlagAnnotationView: MKAnnotationView?
        private var pendingStopFlagData: (flag: String, city: String, subtitle: String)?
        private var renderContinuation: CheckedContinuation<Bool, Never>?

        func cancel() {
            task?.cancel()
        }

        /// Czeka na PRAWDZIWY sygnał MapKit (`mapViewDidFinishRenderingMap`)
        /// że kafelki są gotowe — ten sam mechanizm co eksport
        /// (`TravelMapVideoRenderer.MapRenderDelegate`), zamiast zgadywania
        /// "ile sekund powinno wystarczyć". REALNY BUG znaleziony 01.08.2026
        /// (user: "dalej to samo... szare tło", MIMO wcześniejszego
        /// ustawiania szerokiego widoku od razu) — samo USTAWIENIE kamery
        /// nie gwarantuje że kafelki faktycznie zdążyły się załadować, zanim
        /// zaczynamy animować bliższe zbliżenie; `timeoutSeconds` to tylko
        /// awaryjne zabezpieczenie (np. brak internetu), nie normalna ścieżka.
        /// REALNY BUG znaleziony 01.08.2026 (user: podgląd i zapis oba
        /// "zawieszone" naraz) — `withCheckedContinuation` NIE reaguje samo
        /// z siebie na anulowanie Taska (`isPaused`/`cancel()` na czas
        /// zapisu, patrz `updateUIView`). Bez `withTaskCancellationHandler`
        /// czekanie trwało do KOŃCA limitu (do 6s) zanim podgląd faktycznie
        /// przestawał działać — w tym oknie dalej walczył o zasoby MapKit z
        /// eksportem, dokładnie ten sam problem który `isPaused` miał
        /// naprawić. Teraz anulowanie przerywa czekanie NATYCHMIAST.
        func waitForRender(timeoutSeconds: Double) async -> Bool {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    renderContinuation = continuation
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        self.resumeRender(viaSignal: false)
                    }
                }
            } onCancel: {
                Task { @MainActor in self.resumeRender(viaSignal: false) }
            }
        }

        nonisolated func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered else { return }
            Task { @MainActor in self.resumeRender(viaSignal: true) }
        }

        private func resumeRender(viaSignal: Bool) {
            guard let renderContinuation else { return }
            self.renderContinuation = nil
            renderContinuation.resume(returning: viaSignal)
        }

        func start(mapView: MKMapView, stops: [TripStop], speedMultiplier: Double, view: TravelLiveMapView) {
            task?.cancel()
            mapView.removeOverlays(mapView.overlays)
            // BUG znaleziony 31.07.2026 (user: "Play Again" pokazywał pustą
            // mapę bez pojazdu) — usuwaliśmy adnotację z mapy, ale NIGDY nie
            // czyściliśmy tej referencji, więc `ensureVehicleAnnotation` w
            // kolejnym przebiegu myślało że pojazd nadal istnieje na mapie
            // (referencja niepusta) i nigdy go nie dodawało ponownie.
            if let vehicleAnnotation { mapView.removeAnnotation(vehicleAnnotation) }
            self.vehicleAnnotation = nil
            vehicleAnnotationView = nil
            if let stopFlagAnnotation { mapView.removeAnnotation(stopFlagAnnotation) }
            self.stopFlagAnnotation = nil
            stopFlagAnnotationView = nil
            currentRouteOverlay = nil
            currentRouteRenderer = nil
            // BUG znaleziony 01.08.2026 (user: pusty, szary ekran w
            // siatce — zrzut ekranu) — "bezpieczny, szeroki widok od razu"
            // (patrz `makeUIView`) był ustawiany TYLKO RAZ, przy pierwszym
            // stworzeniu widoku. Przy "Odtwórz ponownie" kamera zostawała
            // na WŁASNEJ, ostatniej pozycji z poprzedniego przebiegu —
            // jeśli to inny kontynent niż nowy pierwszy przystanek, animacja
            // próbowała doskoczyć tam w 1.2s, a MapKit fizycznie nie zdążył
            // załadować całkiem nowego regionu kafelków w tym czasie.
            // Resetowanie na KAŻDYM starcie (nie tylko pierwszym) naprawia
            // to identycznie dla pierwszego odtworzenia i każdego replay.
            //
            // `ceilingDistance` (12 mln m) → 1 mln m (01.08.2026, user:
            // "jakby ktoś wystrzelił ten samolot") — `ceilingDistance` to
            // dystans dobrany dla PRAWDZIWEGO przelotu międzykontynentalnego
            // (6000km+), nie dla "bezpiecznego, szerokiego kadru na chwilę
            // przed zjazdem". Zjazd animowany niżej (`setCamera`, teraz 2.0s
            // zamiast 1.2s) musiał pokonać 120× zoom (12mln→100tys.) w
            // niecałe 1.2s — nawet z krzywą ease-in-out to wciąż ogromny
            // dystans w krótkim czasie, stąd wrażenie "wystrzelenia". 1 mln
            // metrów to WCIĄŻ szeroki, bezpieczny widok (dużo szerszy niż
            // jakikolwiek pojedynczy odcinek krótszy niż ~500km), ale zjazd
            // to już tylko 10× zoom zamiast 120×.
            if let firstCoordinate = stops.first?.coordinate {
                mapView.camera = MKMapCamera(
                    lookingAtCenter: firstCoordinate, fromDistance: 1_000_000,
                    pitch: 0, heading: 0
                )
            }
            task = Task { [weak mapView] in
                guard let mapView else { return }
                await self.runAnimation(mapView: mapView, stops: stops, speedMultiplier: speedMultiplier, view: view)
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            // `RevealingPolylineRenderer` zamiast zwykłego `MKPolylineRenderer`
            // — patrz komentarz przy tej klasie, poniżej: nakładka niesie
            // PEŁNĄ, docelową ścieżkę odcinka od razu, renderer sam decyduje
            // ile z niej narysować (`revealCount`), więc coordinator nie musi
            // usuwać/dodawać nakładki na każdym kroku animacji.
            var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
            polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
            let renderer = RevealingPolylineRenderer(polyline: polyline)
            renderer.allCoordinates = coordinates
            let transport = (polyline.title.flatMap { TransportMode(rawValue: $0) }) ?? .car
            let scale = Self.canonicalScale(for: mapView)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = RouteProvider.lineWidth(for: transport) * 1.5 * scale
            renderer.lineDashPattern = RouteProvider.lineDashPattern(for: transport).map { NSNumber(value: Double($0) * scale) }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            currentRouteRenderer = renderer
            return renderer
        }

        /// Rozmiary ikon/linii w `TravelMapVideoRenderer.composite` są
        /// dobrane pod KANONICZNY canvas eksportu (1080pt szerokości) i
        /// przeskalowane stamtąd (`scale = size.width / 1080`). Żywa mapa w
        /// podglądzie ma szerokość PRAWDZIWEGO ekranu telefonu (~390-430pt)
        /// — bez tego samego przeliczenia te same stałe (np. `56pt` ikona
        /// pojazdu) wychodzą ~2.5x za duże. REALNY BUG znaleziony
        /// 31.07.2026 (user: "samochód i pociąg wyglądają jak kwadraty") —
        /// źródłowe assety pojazdów są małe (np. `car_top.png` ~98×166px),
        /// więc oversized + upscaled = widocznie pikselowate/blokowe.
        private static func canonicalScale(for mapView: MKMapView) -> CGFloat {
            max(0.2, mapView.bounds.width / 1080)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is VehicleAnnotation {
                let identifier = "vehicle"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.centerOffset = .zero
                vehicleAnnotationView = view
                return view
            }
            if annotation is StopFlagAnnotation {
                let identifier = "stopFlag"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                // `zPriority` ponad pojazdem/trasą — chorągiewka ma być
                // zawsze czytelna na wierzchu, nie zasłaniana przez linię
                // trasy przechodzącą w tym samym miejscu.
                view.zPriority = .max
                // BUG znaleziony 01.08.2026 (user: chorągiewka nigdy się nie
                // pojawiała, ani razu na 3 zrzutach ekranu) — `showStopFlag`
                // ustawiało obrazek na widoku ZARAZ PO `addAnnotation`, ale
                // MapKit nie gwarantuje że ten delegat wykona się w pełni
                // SYNCHRONICZNIE przed powrotem z `addAnnotation`. Ikona
                // pojazdu miała ten sam schemat, ale "leczyła się sama",
                // bo jest odświeżana co klatkę — chorągiewka pokazuje się
                // raz, więc brak trafienia = pusta na całe okno wyświetlania.
                // Naprawa: obrazek budowany TUTAJ, w samym delegacie, z
                // danych zapisanych na koordynatorze PRZED `addAnnotation` —
                // gwarantowana kolejność niezależnie od timingu MapKit.
                if let data = pendingStopFlagData {
                    let (image, anchorOffset) = Self.flagImage(flag: data.flag, city: data.city, subtitle: data.subtitle)
                    view.image = image
                    view.centerOffset = CGPoint(x: 0, y: -anchorOffset)
                }
                stopFlagAnnotationView = view
                return view
            }
            return nil
        }

        /// Odpowiednik `TravelMapVideoRenderer.renderFrames` — ten sam kształt
        /// pętli (odcinek → krok), ale zamiast fotografować mapę i czekać na
        /// `mapViewDidFinishRenderingMap`, animuje PRAWDZIWĄ, widoczną kamerę.
        private func runAnimation(mapView: MKMapView, stops: [TripStop], speedMultiplier: Double, view: TravelLiveMapView) async {
            guard stops.count >= 2 else {
                view.onError(L("This trip needs at least two stops with a location set."))
                return
            }

            // Sam fakt USTAWIENIA kamery (w `start()`) nie gwarantuje że
            // kafelki faktycznie zdążyły się załadować — REALNY BUG
            // znaleziony 01.08.2026 (user: "dalej to samo... szare tło",
            // MIMO wcześniejszego ustawiania szerokiego widoku od razu).
            // Ustawiamy ponownie TUTAJ (blisko w czasie, żeby zminimalizować
            // okno wyścigu z sygnałem) i CZEKAMY na prawdziwe potwierdzenie
            // MapKit, zanim ruszymy jakąkolwiek animacją — ten sam mechanizm
            // co eksport (`TravelMapVideoRenderer.MapRenderDelegate`).
            //
            // REALNY BUG znaleziony 01.08.2026 (user: "dalej wystrzela jak z
            // procy" — DOKŁADNIE ten sam objaw co przed naprawą w `start()`)
            // — ten reset używał `TravelCinematics.ceilingDistance` (12 mln m),
            // czyli po cichu KASOWAŁ naprawę z `start()` (1 mln m zamiast 12
            // mln), bo wykonuje się PO NIEJ, tuż przed samym zjazdem kamery
            // niżej. Zjazd i tak zawsze startował ze wszystkich 12 mln metrów
            // (120× zoom w 2s), nie z 1 mln (10× zoom) — dwie osobne, dobrze
            // uzasadnione naprawy (szare kafelki / wystrzelony samolot)
            // ubocznie się wykasowały. `1_000_000` tutaj też — wciąż
            // wystarczająco szeroki bezpieczny widok dla MapKit, żeby mieć co
            // renderować, ale bez cofania naprawy zjazdu.
            if let firstCoordinate = stops.first?.coordinate {
                mapView.camera = MKMapCamera(
                    lookingAtCenter: firstCoordinate, fromDistance: 1_000_000,
                    pitch: 0, heading: 0
                )
                _ = await waitForRender(timeoutSeconds: 6.0)
                if Task.isCancelled { return }
                // Prefetch pierwszego przystanku W TLE (fire-and-forget,
                // ten sam mechanizm co edytor trasy) — 4s zjazdu establishing
                // shot niżej + 5s postoju to naturalny zapas czasu, żeby
                // kafelki bliskiego zoomu zdążyły się ściągnąć zanim
                // faktycznie tam dotrzemy.
                MapTilePrefetcher.prefetch(coordinate: firstCoordinate, mapTheme: view.mapTheme)
                // Dodatkowe 2s→3s przed startem podglądu (01.08.2026, user:
                // "widzimy szare przebłyski... 2 sek powinno wystarczyć do
                // załadowania się mapy"; 02.08.2026, user: "możemy dać
                // sekundę extra, powinno załadować wszystko co trzeba") —
                // `waitForRender` potwierdza tylko że MapKit ZACZĄŁ
                // renderować ten widok, nie że WSZYSTKIE kafelki (zwłaszcza
                // satelitarne, teraz domyślne) faktycznie dociągnęły się w
                // pełnej rozdzielczości. Zwykły, stały zapas czasu — prosty,
                // bezpośredni fix zamiast dalszego kombinowania z sygnałami
                // renderowania.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
            }

            let stopConditions: [LightingCondition] = stops.map { stop in
                guard let coordinate = stop.coordinate, let arrivalDate = stop.arrivalDate else { return .day }
                return CinematicLighting.condition(latitude: coordinate.latitude, longitude: coordinate.longitude, date: arrivalDate)
            }

            func updateLighting(legIndex: Int, progress: Double) {
                guard stopConditions.count >= 2 else { return }
                let clampedIndex = max(0, min(stopConditions.count - 2, legIndex))
                view.onLightingUpdate(stopConditions[clampedIndex], stopConditions[clampedIndex + 1], progress)
            }

            let baseStepSeconds = 0.045 / max(0.1, speedMultiplier)

            var completedLegsKm: Double = 0

            // Kadr startowy — kamera na pierwszym przystanku, karta przyjazdu
            // widoczna, zanim ruszymy (ten sam beat co `renderFrames`).
            if let first = stops.first, let firstCoordinate = first.coordinate {
                let firstLegKm = stops.count > 1 ? stops[1].coordinate.map { RouteProvider.straightDistanceKm(from: firstCoordinate, to: $0) } : nil
                let firstTransport = stops.count > 1 ? stops[1].transport : .plane
                let establishingState = TravelCinematics.frameState(progress: 0, legDistanceKm: firstLegKm ?? .infinity, transport: firstTransport)
                // BUG znaleziony 01.08.2026 (user: "punkty startu i
                // lądowania się przemieszczają, nie zostają na mapie") —
                // dla lotów establishing shot centruje się od razu na
                // ŚRODKU CAŁEGO odcinka (nie na samym punkcie startu), żeby
                // nie było skoku środka kamery w chwili gdy samolot zacznie
                // lecieć (patrz ten sam środek użyty niżej w pętli lotu).
                let establishingCenter: CLLocationCoordinate2D
                if firstTransport == .plane, (firstLegKm ?? .infinity) <= TravelCinematics.longFlightFollowThresholdKm,
                   stops.count > 1, let secondCoordinate = stops[1].coordinate {
                    establishingCenter = RouteProvider.midpoint(from: firstCoordinate, to: secondCoordinate)
                } else {
                    establishingCenter = firstCoordinate
                }
                // Dłuższy zjazd (0.4s→1.2s→2.0s, 01.08.2026, user: "jakby
                // ktoś wystrzelił ten samolot") — razem z mniejszym
                // dystansem resetu (patrz `start()`, 1 mln zamiast 12 mln
                // metrów) 2.0s daje naprawdę łagodny, czytelny zjazd zamiast
                // gwałtownego skoku zoomu.
                // 4.0s→2.0s (01.08.2026, user po teście: "na 2s był ok, na 4
                // jest za długi") — POTWIERDZONA wartość, nie ruszać bez
                // nowego testu.
                setCamera(mapView, center: establishingCenter, state: establishingState, duration: 2.0)
                showStopFlag(mapView: mapView, stop: first)
                view.onDistanceUpdate(0)
                updateLighting(legIndex: 0, progress: 0)
                // ROZDZIELONE 01.08.2026 (user, mocno: "czas pokazywania
                // miejscowości... nie ma być wolniejszy") — zjazd (ruch
                // kamery) i postój (karta z nazwą miasta) to dwa OSOBNE
                // odczekania, żeby zmiana jednego nie naciągała drugiego.
                try? await Task.sleep(nanoseconds: UInt64(2.0 / max(0.1, speedMultiplier) * 1_000_000_000))
                if Task.isCancelled { return }
                // 3.0s→1.5s→0.4s DLA LOTÓW (01.08.2026, user: "samolot na
                // lotnisku nie musi być pokazany jak stoi, wystarczy jak
                // leci prawidłowo") — samolot nie musi "stać" na płycie
                // lotniska tak długo jak inne środki transportu; 0.4s to
                // tyle, żeby karta z nazwą miasta zdążyła się przeczytać,
                // ale bez zbędnego czekania na nieruchomym samolocie.
                // Pozostałe środki transportu zostają na 1.5s (bez zmian).
                let departureHold = firstTransport == .plane ? 0.4 : 0.75
                try? await Task.sleep(nanoseconds: UInt64(departureHold / max(0.1, speedMultiplier) * 1_000_000_000))
                if Task.isCancelled { return }
                hideStopFlag(mapView: mapView)
            }

            for legIndex in 0..<(stops.count - 1) {
                if Task.isCancelled { return }
                let from = stops[legIndex]
                let to = stops[legIndex + 1]
                guard let fromCoordinate = from.coordinate, let toCoordinate = to.coordinate else { continue }

                let result = await RouteProvider.route(from: fromCoordinate, to: toCoordinate, transport: to.transport)
                let path = RouteProvider.cinematicPath(result.path)
                let legDistanceKm = result.distanceKm
                guard path.count > 1 else { continue }

                // BUG znaleziony 01.08.2026 (user: "punkty startu i
                // lądowania się przemieszczają, nie zostają na mapie",
                // potwierdzone piksel po pikselu — karta startu wyjeżdżała
                // poza krawędź ekranu w połowie długiego lotu) — dla
                // KRÓTKICH/ŚREDNICH lotów kamera NIE podąża za bieżącą
                // pozycją samolotu, tylko trzyma STAŁY środek w połowie
                // drogi między startem a celem przez CAŁY odcinek.
                // Pozostałe środki transportu bez zmian (kamera dalej
                // podąża za pojazdem).
                //
                // BUG znaleziony 04.08.2026 (user, trasa Grenlandia/Kanada→
                // Afryka Zach., kilka tys. km) — ten sam stały, szeroki
                // kadr dla BARDZO długich lotów sprawiał że samolot ginął w
                // ogromnym, niezmiennym kadrze oceanu. Powyżej
                // `longFlightFollowThresholdKm` wracamy do kamery
                // podążającej (jak reszta środków transportu) — patrz
                // komentarz przy stałej w `TravelCinematics.swift`. Próg
                // dobrany tak, żeby NIE dotykać zakresu z buga wyżej
                // (01.08 — krótsze loty zostają na starym, sprawdzonym
                // zachowaniu).
                let legCameraCenter: CLLocationCoordinate2D? = (to.transport == .plane && legDistanceKm <= TravelCinematics.longFlightFollowThresholdKm)
                    ? RouteProvider.midpoint(from: fromCoordinate, to: toCoordinate)
                    : nil

                ensureVehicleAnnotation(mapView: mapView, at: fromCoordinate)
                beginRouteOverlay(mapView, allCoordinates: path, transport: to.transport)
                // Prefetch W TLE celu TEGO odcinka — cały czas lotu (kilka-
                // kilkanaście sekund) to zapas czasu na ściągnięcie kafelków,
                // zero dodatkowego widocznego czekania (user: "nie podoba mi
                // się" blokujący ekran ładowania, wycofany na rzecz tego).
                MapTilePrefetcher.prefetch(coordinate: toCoordinate, mapTheme: view.mapTheme)
                // Bug znaleziony 04.08.2026 (user, długi lot z kamerą
                // podążającą — patrz `legCameraCenter` wyżej: "klatkuje") —
                // powyższy prefetch celuje TYLKO w końcowy punkt odcinka.
                // Dla kamery TRZYMAJĄCEJ STAŁY środek (krótkie loty) to
                // wystarczało (kamera nigdy nie odwiedza nic innego). Dla
                // kamery PODĄŻAJĄCEJ (teraz też długie loty) kamera
                // przelatuje przez WIELE pośrednich miejsc na trasie, które
                // nigdy nie dostawały sygnału "ściągnij się wcześniej" —
                // stąd klatkowanie (MapKit dogania się z kafelkami w locie).
                // Dogrywamy kilka punktów pośrednich wzdłuż `path`, ten sam
                // fire-and-forget prefetch, zero dodatkowego czekania.
                if legCameraCenter == nil, path.count > 2 {
                    let sampleCount = 5
                    for i in 1...sampleCount {
                        let index = min(path.count - 1, (path.count - 1) * i / (sampleCount + 1))
                        MapTilePrefetcher.prefetch(coordinate: path[index], mapTheme: view.mapTheme)
                    }
                }

                let steps = TravelCinematics.legStepCount(baseStepSeconds: baseStepSeconds)
                var previousHeading: Double?
                var smoothedLean: Double = 0
                var lastAnimatedPoint = fromCoordinate

                for step in 0...steps {
                    if Task.isCancelled { return }
                    // Krzywa prędkości samego POJAZDU (nie tylko kamery) —
                    // user (dzieląc się analizą): "sama animacja... problem
                    // to reżyseria kamery... zrobiłbym krzywą prędkości: miękki
                    // start, płynne przyspieszanie, stały lot, płynne
                    // wyhamowanie". Wcześniej każdy krok pokonywał TAKI SAM
                    // kawałek trasy (`step/steps` wprost) — pojazd jechał ze
                    // stałą prędkością, tylko kamera miała krzywą. Teraz
                    // `progress` (pozycja NA TRASIE, dystans, oświetlenie,
                    // ORAZ obwiednia zoomu kamery — wszystko liczone z TEGO
                    // samego, jednego `progress`) jest przepuszczone przez
                    // `easeInOutCubic` (już istniejącą, sprawdzoną krzywą w
                    // tym pliku) — wolno na starcie/końcu odcinka, szybciej w
                    // środku, bez nowej matematyki do przetestowania.
                    let rawProgress = Double(step) / Double(steps)
                    let progress = TravelCinematics.easeInOutCubic(rawProgress)
                    // Interpolacja MIĘDZY sąsiednimi punktami ścieżki
                    // (12.08.2026, ten sam fix co eksport — patrz
                    // `RouteProvider.interpolate`) zamiast zaokrąglania w
                    // dół — bez tego pojazd zamierał w miejscu tuż przed
                    // przyjazdem, gdzie `easeInOutCubic` spłaszcza się
                    // najmocniej (pierwotnie znalezione w eksporcie, ale ta
                    // sama matematyka pozycji, więc ten sam problem).
                    let rawIndex = Double(path.count - 1) * progress
                    let pointIndex = Int(rawIndex)
                    let nextIndex = min(path.count - 1, pointIndex + 1)
                    let previousIndex = max(0, pointIndex - 1)
                    let point = RouteProvider.interpolate(from: path[pointIndex], to: path[nextIndex], fraction: rawIndex - Double(pointIndex))
                    lastAnimatedPoint = point

                    let heading = RouteProvider.bearing(from: path[previousIndex], to: point)
                    let rawLean = TravelCinematics.rawLeanDegrees(previousHeading: previousHeading, currentHeading: heading)
                    smoothedLean = TravelCinematics.smoothedLean(previous: smoothedLean, target: rawLean)
                    previousHeading = heading

                    // BUG znaleziony 01.08.2026 (user: "dlaczego samolot
                    // przeskakuje?") — pierwszy krok KAŻDEGO odcinka (poza
                    // samym początkiem trasy) robił twardy skok kamery BEZ
                    // animacji (dawny trik na szare kafelki, sprzed
                    // dzisiejszego prefetchu w tle i krzywej ruchu pojazdu).
                    // Teraz kafelki celu tego odcinka są już ściągane w tle
                    // od momentu startu poprzedniego odcinka (patrz
                    // `MapTilePrefetcher.prefetch` wyżej), a odcinki są
                    // geograficznie ciągłe (departure ≈ poprzednie arrival)
                    // — skok nie jest już potrzebny. Krok 0 animuje się TERAZ
                    // dokładnie tak samo jak każdy inny krok, bez wyjątku.
                    let frameState = TravelCinematics.frameState(progress: progress, legDistanceKm: legDistanceKm, transport: to.transport)
                    setCamera(mapView, center: legCameraCenter ?? point, state: frameState, duration: baseStepSeconds)
                    updateRouteReveal(count: pointIndex + 1)
                    updateVehicle(
                        mapView: mapView, coordinate: point, transport: to.transport, bearing: heading,
                        leanDegrees: smoothedLean, iconScale: frameState.iconScale
                    )
                    view.onDistanceUpdate(completedLegsKm + legDistanceKm * progress)
                    updateLighting(legIndex: legIndex, progress: progress)

                    try? await Task.sleep(nanoseconds: UInt64(max(0.001, baseStepSeconds) * 1_000_000_000))
                }

                completedLegsKm += legDistanceKm

                // Kamera zostaje na współrzędnej OSTATNIEJ animowanej klatki,
                // nie dokładnym `toCoordinate` — unika mikro-skoku przy
                // lądowaniu (ten sam zabieg co eksport).
                let arrivalState = TravelCinematics.frameState(progress: 1.0, legDistanceKm: legDistanceKm, transport: to.transport)
                setCamera(mapView, center: legCameraCenter ?? lastAnimatedPoint, state: arrivalState, duration: 2.5)
                // NIE chowamy już pojazdu na czas przystanku (01.08.2026,
                // user: "wygląda jakby gdzieś utknął") — zniknięcie na
                // 1.8s+ wyglądało jak zawieszenie animacji, nie jak pauza.
                // Pojazd zostaje widoczny, zaparkowany na miejscu przyjazdu.
                showStopFlag(mapView: mapView, stop: to)
                view.onDistanceUpdate(completedLegsKm)
                // ROZDZIELONE 01.08.2026 — zjazd lądowania (ruch kamery, 2.5s)
                // i postój pokazujący kartę to dwa osobne odczekania.
                try? await Task.sleep(nanoseconds: UInt64(2.5 / max(0.1, speedMultiplier) * 1_000_000_000))
                if Task.isCancelled { return }
                // 2.5s→1.5s→0.4s DLA LOTÓW (01.08.2026, user: "samolot na
                // lotnisku nie musi być pokazany jak stoi, wystarczy jak
                // leci prawidłowo") — ten sam powód co postój przed startem
                // wyżej. Pozostałe środki transportu zostają na 1.5s.
                let arrivalHold = to.transport == .plane ? 0.4 : 0.75
                try? await Task.sleep(nanoseconds: UInt64(arrivalHold / max(0.1, speedMultiplier) * 1_000_000_000))
                if Task.isCancelled { return }
                hideStopFlag(mapView: mapView)
            }

            mapView.removeOverlays(mapView.overlays)
            if let vehicleAnnotation { mapView.removeAnnotation(vehicleAnnotation) }
            self.vehicleAnnotation = nil
            if let stopFlagAnnotation { mapView.removeAnnotation(stopFlagAnnotation) }
            self.stopFlagAnnotation = nil
            currentRouteOverlay = nil
            currentRouteRenderer = nil
            view.onFinished()
        }

        // BUG znaleziony 01.08.2026 (user: "jak startuje jest przyspieszenie
        // i jak ląduje są jakieś niedoskonałości") — `.curveLinear` zmienia
        // DYSTANS kamery ze stałą szybkością w czasie, ale percepcja zoomu
        // jest LOGARYTMICZNA: liniowe zejście z bardzo szerokiego widoku
        // (reset bezpieczeństwa na starcie, patrz `start()`) do bliskiego
        // zbliżenia w 1.2s spędza większość czasu "wysoko" i gwałtownie
        // przyspiesza pod koniec, tuż przed dotarciem do celu — dokładnie
        // ten efekt, który user opisał. `.curveEaseInOut` daje wolny
        // start/koniec, dopasowany do tego jak oko faktycznie odbiera zoom.
        private func setCamera(_ mapView: MKMapView, center: CLLocationCoordinate2D, state: TravelCinematics.FrameState, duration: TimeInterval) {
            let camera = MKMapCamera(lookingAtCenter: center, fromDistance: state.cameraDistance, pitch: state.cameraPitch, heading: 0)
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                mapView.camera = camera
            }
        }

        /// Nakładka trasy dodawana RAZ na odcinek, z PEŁNĄ docelową ścieżką —
        /// user 01.08.2026: "czy da się to zrobić płynnie bez klatkowania?".
        /// Poprzednio (`setRouteOverlay`, teraz `updateRouteReveal`) każdy z
        /// ~190 kroków odcinka USUWAŁ i DODAWAŁ nową nakładkę z rosnącą listą
        /// punktów — MapKit musiał za każdym razem projektować i renderować
        /// całą ścieżkę od nowa, realny koszt klatkowania. Teraz nakładka
        /// (i jej `RevealingPolylineRenderer`) powstaje raz, a każdy krok
        /// tylko podnosi `revealCount` o jeden punkt (`setNeedsDisplay()`),
        /// bez ponownego dodawania nakładki do mapy.
        private func beginRouteOverlay(_ mapView: MKMapView, allCoordinates: [CLLocationCoordinate2D], transport: TransportMode) {
            if let currentRouteOverlay { mapView.removeOverlay(currentRouteOverlay) }
            currentRouteRenderer = nil
            guard allCoordinates.count > 1 else { currentRouteOverlay = nil; return }
            let polyline = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)
            polyline.title = transport.rawValue
            mapView.addOverlay(polyline)
            currentRouteOverlay = polyline
            // Uwaga: `rendererFor:` (i sam `RevealingPolylineRenderer.init`,
            // które domyślnie ustawia `revealCount = 1`) wykonuje się
            // dopiero na kolejnym cyklu rysowania MapKit, NIE synchronicznie
            // tutaj — stąd `revealCount` startowe jest ustawione w samym
            // inicie renderera, nie próbujemy tego robić w tym miejscu.
        }

        private func updateRouteReveal(count: Int) {
            currentRouteRenderer?.revealCount = count
        }

        private func ensureVehicleAnnotation(mapView: MKMapView, at coordinate: CLLocationCoordinate2D) {
            if let vehicleAnnotation {
                vehicleAnnotation.coordinate = coordinate
                showVehicle()
                return
            }
            let annotation = VehicleAnnotation(coordinate: coordinate)
            vehicleAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private func hideVehicle() {
            vehicleAnnotationView?.alpha = 0
        }

        private func showVehicle() {
            vehicleAnnotationView?.alpha = 1
        }

        /// Wędrówka rysowana emoji-tekstem (ta sama konwencja co
        /// `TravelMapVideoRenderer.composite`), pozostałe środki transportu —
        /// wycięte assety z `VehicleIconSet`. Obrót BEZ negacji — `leanDegrees`
        /// doklejony do namiaru, nigdy nie zasila samego `bearing` przekazanego
        /// do `resolve` (zmieniłoby wybór assetu left/right/top w połowie
        /// zakrętu).
        private func updateVehicle(mapView: MKMapView, coordinate: CLLocationCoordinate2D, transport: TransportMode, bearing: Double, leanDegrees: Double, iconScale: Double) {
            vehicleAnnotation?.coordinate = coordinate
            guard let view = vehicleAnnotationView else { return }
            view.alpha = 1
            let scale = Self.canonicalScale(for: mapView)
            if transport == .hiking {
                let size = 52 * iconScale * scale
                view.image = Self.emojiImage(transport.emoji, pointSize: size)
                view.transform = .identity
            } else {
                let resolved = VehicleIconSet.resolve(transport: transport, bearing: bearing)
                let image = UIImage(named: resolved.assetName)
                view.image = image
                // BUG znaleziony 31.07.2026 (user: "sprawdź jaki kształt ma
                // samochód" — 98×166px, wydłużony, NIE kwadrat) — wymuszanie
                // `width == height` ściskało naturalnie podłużne assety
                // (samochód/pociąg/bok łodzi) w kwadrat. Wysokość referencyjna
                // (`iconSize`), szerokość dopasowana do PRAWDZIWEJ proporcji
                // obrazka źródłowego. Bazowa wysokość 56→90 (31.07.2026,
                // user: "wyglądają jak miniaturki, niektórzy nie będą mogli
                // ich zobaczyć") — poprawiony kształt bez powiększenia
                // wypadł zbyt drobno na prawdziwym ekranie telefonu.
                let iconHeight = 90 * iconScale * scale
                let aspect = (image?.size.height ?? 0) > 0 ? (image!.size.width / image!.size.height) : 1
                view.bounds = CGRect(x: 0, y: 0, width: iconHeight * aspect, height: iconHeight)
                view.transform = CGAffineTransform(rotationAngle: (resolved.rotationDegrees + leanDegrees) * .pi / 180)
            }
        }

        private static func emojiImage(_ emoji: String, pointSize: CGFloat) -> UIImage {
            let font = UIFont.systemFont(ofSize: pointSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let size = (emoji as NSString).size(withAttributes: attrs)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                (emoji as NSString).draw(at: .zero, withAttributes: attrs)
            }
        }

        // MARK: - Chorągiewka przystanku

        /// Zamiast karty przyklejonej na sztywno do dołu ekranu (31.07.2026,
        /// user: "zamiast na dole chmurki... flaga gdzie flaga mówi o
        /// nazwie a trzon pokazuje punkt z którego się startuje i gdzie się
        /// zatrzymujemy") — prawdziwa `MKAnnotationView` z chorągiewką nad
        /// trzonkiem, którego DÓŁ (nie środek obrazka) siedzi dokładnie na
        /// współrzędnej przystanku (`centerOffset`, ten sam trik co
        /// klasyczna pinezka-łezka w Mapach).
        private func showStopFlag(mapView: MKMapView, stop: TripStop) {
            guard let coordinate = stop.coordinate else { return }
            // `hideStopFlag` zawsze w pełni usuwa poprzednią adnotację, więc
            // tutaj zawsze tworzymy nową — dane muszą być zapisane PRZED
            // `addAnnotation`, bo obrazek budowany jest w delegacie
            // (`mapView(_:viewFor:)`), nie tutaj (patrz komentarz tam).
            let flag = CityGeocoder.flagEmoji(countryCode: stop.countryCode)
            pendingStopFlagData = (flag: flag, city: stop.cityName, subtitle: Self.subtitle(for: stop))
            let annotation = StopFlagAnnotation(coordinate: coordinate)
            stopFlagAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private func hideStopFlag(mapView: MKMapView) {
            guard let stopFlagAnnotation else { return }
            mapView.removeAnnotation(stopFlagAnnotation)
            self.stopFlagAnnotation = nil
            stopFlagAnnotationView = nil
        }

        /// Kraj + data pobytu (jeśli ustawiona) w jednej linii — ta sama
        /// logika co `TravelMapVideoRenderer.subtitle`.
        private static func subtitle(for stop: TripStop) -> String {
            guard let arrivalDate = stop.arrivalDate else { return stop.country ?? "" }
            let formatted = dateFormatter.string(from: arrivalDate)
            guard let country = stop.country, !country.isEmpty else { return formatted }
            return "\(country) · \(formatted)"
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter
        }()

        /// Rysuje chorągiewkę (tło + flaga/nazwa/podtytuł) NAD pionowym
        /// trzonkiem zakończonym kropką — zwraca gotowy obraz oraz
        /// `anchorOffset` (połowa wysokości obrazu), którym trzeba przesunąć
        /// `centerOffset` żeby DÓŁ trzonka (kropka) wylądował dokładnie na
        /// współrzędnej, nie środek obrazka.
        ///
        /// BEZ mnożnika `size.width / 1080` (inaczej niż ikona pojazdu) —
        /// REALNY BUG znaleziony 01.08.2026 (user: "znaczniki miejsc są
        /// mniejsze od nazw na mapie, mają być większe"): ten mnożnik ma
        /// sens dla ikon pojazdów, które muszą wizualnie pasować do
        /// eksportu, ale chorągiewka to zwykły element UI — przy typowej
        /// szerokości ekranu (~390-430pt) ten sam mnożnik dawał ~0.36-0.4,
        /// więc "20pt" czcionki wychodziło jako ~7-8pt, dużo mniejsze niż
        /// własne etykiety miast Apple na satelicie. Stałe rozmiary w
        /// prawdziwych punktach ekranu, jak odznaka dystansu.
        private static func flagImage(flag: String, city: String, subtitle: String) -> (image: UIImage, anchorOffset: CGFloat) {
            // 22pt→17pt (04.08.2026, user: pełne, długie nazwy lotnisk nie
            // mieściły się na ekranie w podglądzie — "nie musi skracać,
            // wystarczy zrobić trochę mniejsze napisy") — mniejsza czcionka
            // zamiast skracania tekstu, plus zawijanie do 2 linii niżej
            // jako dodatkowe zabezpieczenie dla naprawdę długich nazw.
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white
            ]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            let title = "\(flag)  \(city.uppercased())" as NSString
            let subtitleText = subtitle as NSString

            // Bug znaleziony 04.08.2026 (user: "cała nazwa lotniska się nie
            // łapie na ekranie") — druga warstwa zabezpieczenia obok
            // skracania nazwy w `showStopFlag` (to tu działa niezależnie od
            // TEGO skąd przyszedł tekst — miasto z ręcznego wpisania też
            // może być długie). Tytuł zawija się do maks. 2 linii zamiast
            // liczyć szerokość karty z jednej, dowolnie długiej linii —
            // `boundingRect(.usesLineFragmentOrigin)` zamiast `size(...)`.
            let maxTitleWidth: CGFloat = 260
            let titleBounds = title.boundingRect(
                with: CGSize(width: maxTitleWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil
            )
            let titleSize = CGSize(width: min(titleBounds.width, maxTitleWidth).rounded(.up), height: titleBounds.height.rounded(.up))
            let subtitleSize = subtitle.isEmpty ? .zero : subtitleText.size(withAttributes: subtitleAttrs)

            let padding: CGFloat = 14
            let pennantWidth = max(titleSize.width, min(subtitleSize.width, maxTitleWidth)) + padding * 2
            let pennantHeight = titleSize.height + (subtitle.isEmpty ? 0 : subtitleSize.height + 3) + padding * 2
            let poleHeight: CGFloat = 44
            let dotRadius: CGFloat = 6

            let totalSize = CGSize(width: pennantWidth, height: pennantHeight + poleHeight + dotRadius * 2)
            let poleX = pennantWidth / 2

            let renderer = UIGraphicsImageRenderer(size: totalSize)
            let image = renderer.image { ctx in
                let cg = ctx.cgContext
                let pennantRect = CGRect(x: 0, y: 0, width: pennantWidth, height: pennantHeight)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
                cg.addPath(UIBezierPath(roundedRect: pennantRect, cornerRadius: 10).cgPath)
                cg.fillPath()
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
                cg.setLineWidth(1)
                cg.addPath(UIBezierPath(roundedRect: pennantRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10).cgPath)
                cg.strokePath()

                var textY = padding
                title.draw(
                    with: CGRect(x: padding, y: textY, width: titleSize.width, height: titleSize.height),
                    options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil
                )
                if !subtitle.isEmpty {
                    textY += titleSize.height + 3
                    subtitleText.draw(at: CGPoint(x: padding, y: textY), withAttributes: subtitleAttrs)
                }

                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(2.5)
                cg.move(to: CGPoint(x: poleX, y: pennantHeight))
                cg.addLine(to: CGPoint(x: poleX, y: pennantHeight + poleHeight))
                cg.strokePath()

                let dotRect = CGRect(x: poleX - dotRadius, y: pennantHeight + poleHeight, width: dotRadius * 2, height: dotRadius * 2)
                cg.setFillColor(UIColor.systemBlue.cgColor)
                cg.addPath(UIBezierPath(ovalIn: dotRect).cgPath)
                cg.fillPath()
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(2)
                cg.addPath(UIBezierPath(ovalIn: dotRect).cgPath)
                cg.strokePath()
            }
            return (image, totalSize.height / 2)
        }
    }

    /// Renderer trasy, który NIE wymaga usuwania/dodawania całej nakładki na
    /// każdym kroku animacji — user 01.08.2026: "czy da się to zrobić płynnie
    /// bez klatkowania?". Poprzednio KAŻDY z ~190 kroków odcinka usuwał i
    /// dodawał NOWY `MKPolyline` z rosnącą listą punktów — MapKit musiał za
    /// każdym razem projektować i renderować całą ścieżkę od nowa, realny
    /// koszt powodujący klatkowanie. Teraz nakładka niesie od razu PEŁNĄ,
    /// docelową ścieżkę odcinka (dodaną RAZ), a ten renderer rysuje tylko
    /// pierwsze `revealCount` punktów — jedyna rzecz aktualizowana co krok.
    // BUG znaleziony 01.08.2026 (user: "wywaliło mi apkę jak włączyłem
    // podgląd trasy") — crash: "Use of unimplemented initializer
    // 'init(overlay:)'". Własny inicjalizator (`init(polyline:allCoordinates:)`)
    // psuł wymagany przez MapKit łańcuch dziedziczenia designated initializerów
    // `MKOverlayRenderer`. Naprawa: BEZ własnego initu — `allCoordinates`/
    // `revealCount` to zwykłe, mutowalne właściwości ustawiane PO utworzeniu
    // obiektu (przez zwykły `MKPolylineRenderer(polyline:)`), nie przez
    // parametry konstruktora.
    final class RevealingPolylineRenderer: MKPolylineRenderer {
        var allCoordinates: [CLLocationCoordinate2D] = []
        var revealCount: Int = 1 {
            didSet {
                guard revealCount != oldValue else { return }
                invalidatePath()
                setNeedsDisplay()
            }
        }

        override func createPath() {
            let count = min(revealCount, allCoordinates.count)
            guard count > 1 else { self.path = nil; return }
            let cgPath = CGMutablePath()
            cgPath.move(to: point(for: MKMapPoint(allCoordinates[0])))
            for index in 1..<count {
                cgPath.addLine(to: point(for: MKMapPoint(allCoordinates[index])))
            }
            self.path = cgPath
        }
    }

    /// Adnotacja chorągiewki przystanku — jedna naraz (start/przyjazd),
    /// pokazywana/ukrywana zamiast tworzona od nowa dla każdego przystanku.
    final class StopFlagAnnotation: NSObject, MKAnnotation {
        @objc dynamic var coordinate: CLLocationCoordinate2D
        init(coordinate: CLLocationCoordinate2D) {
            self.coordinate = coordinate
        }
    }

    /// Prosta, pojedyncza adnotacja pojazdu — `coordinate` oznaczona
    /// `@objc dynamic`, żeby MapKit sam repozycjonował widok przez KVO,
    /// bez ręcznego usuwania/dodawania adnotacji na każdy krok.
    final class VehicleAnnotation: NSObject, MKAnnotation {
        @objc dynamic var coordinate: CLLocationCoordinate2D
        init(coordinate: CLLocationCoordinate2D) {
            self.coordinate = coordinate
        }
    }
}
