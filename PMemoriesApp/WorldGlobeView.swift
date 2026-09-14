import SwiftUI
import MapKit
import SwiftData

/// "Zobacz wszystkie miejsca" — Faza 1 World Globe (30.07.2026): interaktywny,
/// przybliżalny globus ze WSZYSTKIMI odwiedzonymi miejscami naraz (agregacja
/// wszystkich `SavedTrip`, nie animacja jednej podróży jak `TravelMapAnimationView`).
/// Świadomie NOWY widok, nie rozszerzenie `TravelMapVideoRenderer` — tamten
/// silnik piecze płaskie bitmapy do pliku wideo i nie nadaje się do żywej,
/// przesuwalnej mapy. Zacieniowane granice krajów (drugi kawałek oryginalnego
/// pomysłu) świadomie ODŁOŻONE — wymagałyby nowych danych geograficznych
/// (granice krajów), których appka dziś w ogóle nie ma; user potwierdził
/// (30.07.2026) że same pinezki ze zdjęciami wystarczą na Fazę 1.
///
/// Rozszerzone 30.08.2026 (user: "zeby sie pojawialy miejsca na globie bez
/// trasy ale z gps zdjec") — miejsca NIE wymagają już zaplanowanej podróży w
/// Travel Map. Każdy gotowy Memory bez powiązanego przystanku sam w sobie
/// dokłada kandydatów na miejsca, prosto z lokalizacji GPS jego zdjęć (ten
/// sam mechanizm co Smart Route/`TripMemoryMatcher`, `MediaAssetLoader.
/// locationsAndDates`). Przystanki z Travel Map i "surowe" zdjęcia z Memories
/// klastrowane RAZEM (ten sam promień 20km) — jeśli miejsce ma już
/// geokodowany przystanek, jego nazwa wygrywa (bez sieciowego zapytania);
/// czysto "surowe" miejsca dostają nazwę przez jednorazowe odwrotne
/// geokodowanie przy budowaniu listy.
struct WorldGlobeView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @Query private var savedProjects: [SavedProject]
    /// Zamykane RĘCZNIE przed przełączeniem zakładki (`select(_:)`) — user
    /// 30.07.2026: samo ustawienie `selectedTab` nie przenosiło od razu na
    /// Library, dopóki ten ekran (wciśnięty na `NavigationStack` Travel Map)
    /// zostawał na wierzchu — zamknięcie go najpierw usuwa tę przeszkodę.
    @Binding var isPresented: Bool
    @Binding var selectedTab: MainTab
    @Binding var pendingLibraryHighlightIDs: [UUID]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasSetInitialCamera = false
    @State private var selectedPlaceID: String?
    /// Miejsce po tapnięciu, zanim user wybierze akcję (18.08.2026) — steruje
    /// głównym `.confirmationDialog` ("Go to Memory"/"Show Route"). Zastąpiło
    /// dawne `selectedUnlinkedPlace` (który tylko pokazywał komunikat "brak
    /// filmu") — teraz appka ZAWSZE ma coś do zaoferowania (przynajmniej
    /// Show Route ALBO Go to Memory), więc jeden, uniwersalny dialog zamiast
    /// osobnego alertu.
    @State private var actionPlace: GlobePlace?
    /// Drugi dialog — wybór KTÓREJ podróży pokazać trasę, gdy miejsce
    /// odwiedzone w ramach więcej niż jednej (user: "co jeśli jesteśmy w tym
    /// miejscu 2 raz albo przejazdem").
    @State private var tripPickerPlace: GlobePlace?
    @State private var routeOverviewTrip: SavedTrip?
    /// Wynik klastrowania — POLICZONY RAZ przy pojawieniu się ekranu
    /// (`.task`), NIE zwykły computed property jak przed 30.08.2026. Miejsca
    /// "surowe" (bez przystanku) potrzebują odwrotnego geokodowania (sieć,
    /// asynchroniczne) — computed property przeliczałoby to przy KAŻDYM
    /// renderze (np. po zwykłym tapnięciu pinezki), co zasypałoby Apple
    /// odwrotnymi zapytaniami geokodowania bez potrzeby.
    @State private var places: [GlobePlace] = []
    @State private var isLoadingPlaces = true

    /// Zmienia się przy KAŻDEJ zmianie liczby zapisanych filmów/przystanków —
    /// patrz komentarz przy `.task(id:)` w `body`.
    private var placesRebuildTrigger: Int {
        savedProjects.count &+ savedTrips.reduce(0) { $0 &+ $1.stops.count }
    }

    private static let clusterRadiusKm: Double = 20

    var body: some View {
        Group {
            if isLoadingPlaces {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if places.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.heroGradient)
                    Text("No saved places yet")
                        .font(.title3.bold())
                    Text("Save your first trip in Travel Map to see it here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // `Map(selection:)` + `.tag(_:)` — oficjalny mechanizm
                // zaznaczania adnotacji w MapKit/SwiftUI, NIE `.onTapGesture`
                // ani zwykły `Button` w środku `Annotation` — user 30.07.2026:
                // żadne z tamtych dwóch podejść nie odbierało tapnięcia
                // NIEZAWODNIE (mapa sama konkuruje o gest przesuwania/
                // przybliżania z dowolnym gestem/przyciskiem doklejonym do
                // zawartości adnotacji). `selection` to wbudowana ścieżka,
                // którą MapKit obsługuje bez tej konkurencji.
                Map(position: $cameraPosition, selection: $selectedPlaceID) {
                    ForEach(places) { place in
                        Annotation(place.cityName, coordinate: place.coordinate) {
                            GlobePlaceMarker(place: place)
                        }
                        .tag(place.id)
                    }
                }
                .mapStyle(MapTheme.satellite.mapStyle)
                // BUG (01.08.2026, user: pinezki niewidoczne dopóki nie
                // przybliży mapy ręcznie) — `.automatic` na tym stylu
                // (`.hybrid(elevation: .realistic)`, widok globusa) potrafi
                // dobrać START przy kamerze na skalę całej planety, a przy
                // TAK dalekim zoomie MapKit nie renderuje w ogóle adnotacji
                // SwiftUI (znane ograniczenie realistycznego globusa, nie
                // coś naprawialnego samym kodem adnotacji) — pinezki
                // "wracają" dopiero po ręcznym przybliżeniu poniżej tego
                // progu. Naprawa: nie zdawać się na `.automatic`, tylko
                // ustawić START na rozsądnie bliski region dopasowany do
                // zapisanych miejsc — nigdy nie startujemy z niewidocznymi
                // pinezkami. Odpalane teraz z `rebuildPlaces()` (30.08.2026),
                // nie z `.onAppear` tej mapy — `places` może być jeszcze
                // puste w momencie pierwszego pojawienia się `Map`.
                .onChange(of: selectedPlaceID) { _, newValue in
                    guard let newValue, let place = places.first(where: { $0.id == newValue }) else { return }
                    select(place)
                    selectedPlaceID = nil
                }
            }
        }
        // 30.08.2026 — realny bug: user wyeksportował nowe Memory, wrócił na
        // JUŻ WCZEŚNIEJ otwarty ekran Globe, nowe miejsce się nie pojawiło.
        // Zwykłe `.task { }` (bez `id`) liczy się RAZ na cały czas życia tej
        // konkretnej instancji widoku — jeśli SwiftUI nie zniszczyło i nie
        // stworzyło jej od nowa (zależnie od tego jak dokładnie ekran jest
        // prezentowany wyżej w hierarchii), `places` zostaje ze STARYCH
        // danych bez ponownego przeliczenia. `.task(id:)` z wartością zależną
        // od faktycznej liczby zapisanych filmów/przystanków wymusza
        // przeliczenie za KAŻDYM razem gdy te dane się zmienią, niezależnie
        // od tego czy widok jest tą samą instancją.
        .task(id: placesRebuildTrigger) {
            await rebuildPlaces()
        }
        .navigationTitle("Your Places")
        .navigationBarTitleDisplayMode(.inline)
        // Główny dialog po tapnięciu zdjęcia (18.08.2026) — "Go to Memory"
        // TYLKO gdy miejsce ma powiązany film, "Show Route" TYLKO gdy miejsce
        // ma przynajmniej jedną podróż (30.08.2026: miejsca "surowe" z
        // samych zdjęć Memories nie mają ŻADNEJ podróży, więc żadnej trasy
        // do pokazania — dawne założenie "każdy klaster ma trasę z
        // definicji" już nieprawdziwe).
        .confirmationDialog(
            actionPlace?.cityName ?? "",
            isPresented: Binding(get: { actionPlace != nil }, set: { if !$0 { actionPlace = nil } }),
            titleVisibility: .visible
        ) {
            if let place = actionPlace {
                if !place.linkedProjectIDs.isEmpty {
                    Button(L("Go to Memory")) {
                        goToLibrary(projectIDs: place.linkedProjectIDs)
                    }
                }
                if !place.trips.isEmpty {
                    Button(L("Show Route")) {
                        showRoute(for: place)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Drugi dialog — TYLKO gdy miejsce należy do więcej niż jednej
        // podróży (`showRoute(for:)` ustawia to zamiast nawigować od razu).
        .confirmationDialog(
            L("Which trip?"),
            isPresented: Binding(get: { tripPickerPlace != nil }, set: { if !$0 { tripPickerPlace = nil } }),
            titleVisibility: .visible
        ) {
            if let place = tripPickerPlace {
                ForEach(place.trips) { trip in
                    Button(trip.title) {
                        routeOverviewTrip = trip
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .navigationDestination(item: $routeOverviewTrip) { trip in
            TravelRouteOverviewView(trip: trip)
        }
    }

    /// "Show Route" tapnięte (18.08.2026) — nawiguje od razu gdy miejsce
    /// należy do JEDNEJ podróży, inaczej pokazuje `tripPickerPlace` do
    /// wyboru której (user: "przejazdem"/"2 raz w tym miejscu").
    private func showRoute(for place: GlobePlace) {
        if place.trips.count <= 1 {
            routeOverviewTrip = place.trips.first
        } else {
            tripPickerPlace = place
        }
    }

    /// Buduje `places` od zera: zbiera "surowe punkty" z DWÓCH źródeł
    /// (przystanki Travel Map + zdjęcia niepowiązanych Memories), klastruje
    /// je RAZEM po odległości, i dla klastrów bez żadnego przystanku
    /// dociąga nazwę przez jednorazowe odwrotne geokodowanie. Woła się RAZ
    /// na pojawienie się ekranu (`.task` w `body`).
    private func rebuildPlaces() async {
        let points = Self.rawPoints(trips: savedTrips, projects: savedProjects)
        let clusters = Self.clusterPoints(points)
        var built: [GlobePlace] = []
        for cluster in clusters {
            if let place = await Self.place(for: cluster) {
                built.append(place)
            }
        }
        places = built
        isLoadingPlaces = false
        // 31.08.2026 — realny bug (przegląd kodu): `hasSetInitialCamera`
        // ustawiane bezwarunkowo przy PIERWSZYM przebiegu tej funkcji, nawet
        // gdy `places` wtedy było puste (pierwsza wizyta bez żadnych
        // zapisanych miejsc). Skoro `.task(id:)` może teraz przeliczyć
        // `places` WIELOKROTNIE w tej samej sesji widoku (nowy eksport,
        // nowy przystanek — patrz `placesRebuildTrigger`), kamera nigdy nie
        // dopasowywała się do pinezek, które pojawiły się PÓŹNIEJ, jeśli
        // pierwszy przebieg był pusty. Flaga ustawiana TERAZ dopiero gdy
        // `places` faktycznie coś zawiera — pierwsze pojawienie się
        // jakiejkolwiek pinezki wciąż dostaje dopasowaną kamerę.
        guard !hasSetInitialCamera, !places.isEmpty else { return }
        hasSetInitialCamera = true
        // BUG (01.08.2026, user: "flagi i znaczniki dopiero pokazują się
        // jak poruszymy globus") — ustawienie `cameraPosition` WPROST (bez
        // animacji) najwyraźniej nie wystarcza, żeby MapKit w ogóle
        // zbudował widoki adnotacji SwiftUI na widoku globusa (`.realistic`
        // elevation) — dopiero PRAWDZIWY ruch kamery (gest usera albo
        // animowana zmiana) uruchamia tę ścieżkę renderu. `withAnimation`
        // zamiast gołego przypisania — to samo zdarzenie co animowany ruch,
        // nie discrete state jump.
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(Self.initialRegion(for: places))
        }
    }

    /// Jeden "surowy" punkt kandydujący na miejsce, PRZED klastrowaniem —
    /// albo z przystanku Travel Map (`stop` niepuste), albo z lokalizacji
    /// GPS jednego zdjęcia z Memory bez powiązanego przystanku (`memoryProjectID`
    /// niepuste). Nigdy oba naraz.
    private struct RawPoint {
        let coordinate: CLLocationCoordinate2D
        let stop: SavedStop?
        let memoryProjectID: UUID?
        let photoIdentifier: String?
    }

    /// Przystanki Travel Map (jak dotąd) + PO JEDNYM surowym punkcie na
    /// każde zdjęcie z GPS w KAŻDYM Memory, które nie jest jeszcze powiązane
    /// z ŻADNYM przystankiem (30.08.2026, user: "zeby sie pojawialy miejsca
    /// na globie bez trasy ale z gps zdjec") — projekty JUŻ powiązane z
    /// przystankiem pomijane tu celowo, ich miejsce na mapie i tak już
    /// istnieje przez ten przystanek, dublowanie dałoby dwie pinezki w tym
    /// samym miejscu.
    private static func rawPoints(trips: [SavedTrip], projects: [SavedProject]) -> [RawPoint] {
        var points: [RawPoint] = []
        let allStops = trips.flatMap(\.stops).filter { $0.latitude != 0 || $0.longitude != 0 }
        for stop in allStops {
            points.append(RawPoint(coordinate: stop.coordinate, stop: stop, memoryProjectID: nil, photoIdentifier: nil))
        }

        let linkedProjectIDs = Set(allStops.compactMap(\.linkedProjectID))
        for project in projects where !linkedProjectIDs.contains(project.id) {
            let identifiers = project.items.map(\.assetLocalIdentifier).filter { !$0.isEmpty }
            guard !identifiers.isEmpty else { continue }
            let locations = MediaAssetLoader.locationsAndDates(forAssetLocalIdentifiers: identifiers)
            for entry in locations {
                points.append(RawPoint(
                    coordinate: entry.location.coordinate, stop: nil,
                    memoryProjectID: project.id, photoIdentifier: entry.identifier
                ))
            }
        }
        return points
    }

    /// Grupowanie po ODLEGŁOŚCI (ten sam promień 20km i wzorzec co
    /// `SmartRouteDetector`), NIE po dokładnej nazwie — user zgłosił 30.07:
    /// lotnisko przylotu ("Milan–Malpensa Airport") i centrum miasta z
    /// odrębnych zdjęć ("Milan") to dwa RÓŻNE `SavedStop` (różne nazwy z
    /// geokodowania), ale to w oczach usera JEDNO odwiedzone miejsce — bez
    /// grupowania po odległości dostawały dwie osobne, nakładające się
    /// pinezki.
    private static func clusterPoints(_ points: [RawPoint]) -> [[RawPoint]] {
        var clusters: [[RawPoint]] = []
        for point in points {
            let matchIndex = clusters.firstIndex { cluster in
                cluster.contains { RouteProvider.straightDistanceKm(from: $0.coordinate, to: point.coordinate) <= clusterRadiusKm }
            }
            if let matchIndex {
                clusters[matchIndex].append(point)
            } else {
                clusters.append([point])
            }
        }
        return clusters
    }

    /// Jedno miejsce (klaster) może mieć WIĘCEJ NIŻ JEDEN powiązany film —
    /// user 30.07.2026: np. dwie osobne wizyty w tym samym mieście, każda z
    /// innym filmem. `select(_:)` pokazuje wybór po nazwie zamiast po cichu
    /// skakać do pierwszego znalezionego.
    ///
    /// Przystanek (jeśli klaster ma choć jeden) WYGRYWA jako reprezentant —
    /// ma już geokodowaną nazwę, zero sieciowego zapytania. Klaster CZYSTO z
    /// surowych punktów Memories (30.08.2026) dostaje nazwę przez
    /// JEDNORAZOWE odwrotne geokodowanie środka klastra — stąd `async`.
    private static func place(for cluster: [RawPoint]) async -> GlobePlace? {
        guard let first = cluster.first else { return nil }

        let stopsInCluster = cluster.compactMap(\.stop)
        var linkedProjectIDs: [UUID] = []
        for stop in stopsInCluster {
            if let id = stop.linkedProjectID, !linkedProjectIDs.contains(id) { linkedProjectIDs.append(id) }
        }
        for point in cluster {
            if let id = point.memoryProjectID, !linkedProjectIDs.contains(id) { linkedProjectIDs.append(id) }
        }

        // Podróże przechodzące przez to miejsce (18.08.2026, "Show Route" z
        // menu po tapnięciu) — puste dla klastrów czysto z Memories, bez
        // żadnego przystanku.
        var trips: [SavedTrip] = []
        for stop in stopsInCluster {
            if let trip = stop.trip, !trips.contains(where: { $0.id == trip.id }) { trips.append(trip) }
        }

        // 31.08.2026, user: "chce zeby kazde miejsce co bylem w tajlandii mi
        // to pokazywalo... nie tylko puket i chiang mai czy lotnisko" — film
        // powiązany z JEDNYM przystankiem trasy (np. przez alert "Link to
        // your trip?" po eksporcie) liczy się teraz dla KAŻDEGO przystanku
        // TEJ SAMEJ podróży, nie tylko tego jednego. Lotnisko tranzytowe
        // (zero własnych zdjęć w filmie) dostaje "Go to Memory" dzięki temu
        // że Chiang Mai/Phuket z TEJ SAMEJ podróży mają ten film powiązany —
        // cała trasa to jedna wycieczka, jeden film.
        for trip in trips {
            for stop in trip.stops {
                if let id = stop.linkedProjectID, !linkedProjectIDs.contains(id) { linkedProjectIDs.append(id) }
            }
        }

        let representativeStop = stopsInCluster.first(where: { $0.linkedProjectID != nil })
            ?? stopsInCluster.first(where: { $0.representativePhotoIdentifier != nil })
            ?? stopsInCluster.first

        // Bug znaleziony 03.08.2026 (przegląd kodu) — samo `cityName` nie
        // jest unikalne (Paryż we Francji vs. Paryż w Teksasie) — dwa różne
        // klastry mogłyby dostać identyczne `id`. Kod kraju dopisany do
        // nazwy wystarczająco odróżnia realne przypadki. Klastry BEZ
        // przystanku (nazwa jeszcze nieznana w momencie liczenia id)
        // budują id z identyfikatorów projektów zamiast nazwy miasta.
        if let representativeStop {
            let id = cluster.compactMap(\.stop).map { "\($0.cityName)-\($0.countryCode ?? "")" }.joined(separator: "|")
            return GlobePlace(
                id: id, cityName: representativeStop.cityName, countryCode: representativeStop.countryCode,
                coordinate: representativeStop.coordinate,
                representativePhotoIdentifier: representativeStop.representativePhotoIdentifier,
                linkedProjectIDs: linkedProjectIDs, trips: trips
            )
        }

        let photoIdentifier = cluster.first(where: { $0.photoIdentifier != nil })?.photoIdentifier
        let resolved = await CityGeocoder.reverseResolveFull(
            CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
        )
        // 31.08.2026 — realny bug (przegląd kodu): id budowany TYLKO z
        // identyfikatorów projektów w klastrze duplikował się, gdy TEN SAM
        // Memory ma zdjęcia w DWÓCH odległych miejscach (np. Chiang Mai i
        // Phuket, oba bez własnego przystanku) — obie klastry dostawały
        // identyczny string (te same, jedyne id projektu), więc `ForEach`/
        // `Map(selection:)` traciły jednoznaczność który pin to który.
        // Dopisana zaokrąglona współrzędna (unikalna per klaster z definicji
        // grupowania po odległości) naprawia to bez zmiany reszty logiki.
        let coordinateKey = String(format: "%.2f,%.2f", first.coordinate.latitude, first.coordinate.longitude)
        let id = cluster.compactMap { $0.memoryProjectID?.uuidString }.joined(separator: "|") + "@" + coordinateKey
        return GlobePlace(
            id: id.isEmpty ? UUID().uuidString : id,
            cityName: resolved?.city ?? L("Memory"), countryCode: resolved?.countryCode,
            coordinate: first.coordinate, representativePhotoIdentifier: photoIdentifier,
            linkedProjectIDs: linkedProjectIDs, trips: trips
        )
    }

    /// Region dopasowany do zapisanych miejsc, z minimalnym rozpiętością
    /// (żeby jedno/blisko siebie miejsce nie dało zerowego przybliżenia)
    /// i marginesem 60% (żeby pinezki nie stały tuż przy krawędzi ekranu).
    private static func initialRegion(for places: [GlobePlace]) -> MKCoordinateRegion {
        guard !places.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            )
        }
        let lats = places.map(\.coordinate.latitude)
        let lons = places.map(\.coordinate.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.6, 20)
        let lonDelta = max((maxLon - minLon) * 1.6, 20)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    /// 04.08.2026 (user: "jak klikniemy na globus to żeby podświetlało
    /// memories które są w danym mieście") — "Go to Memory" (w dialogu
    /// wyżej) podświetla WSZYSTKIE powiązane filmy naraz, zamiast zmuszać
    /// do wybrania jednego.
    ///
    /// 18.08.2026 — tapnięcie nie skacze już WPROST donikąd, tylko otwiera
    /// `actionPlace` (dialog z "Go to Memory"/"Show Route" wyżej w `body`) —
    /// user: "co jeśli jesteśmy w tym miejscu 2 raz albo przejazdem, czy
    /// możemy po naciśnięciu zdjęcia na mapie mieć menu".
    private func select(_ place: GlobePlace) {
        actionPlace = place
    }

    private func goToLibrary(projectIDs: [UUID]) {
        pendingLibraryHighlightIDs = projectIDs
        isPresented = false
        selectedTab = .library
    }
}

private struct GlobePlace: Identifiable {
    let id: String
    let cityName: String
    let countryCode: String?
    let coordinate: CLLocationCoordinate2D
    let representativePhotoIdentifier: String?
    let linkedProjectIDs: [UUID]
    /// Podróże przechodzące przez to miejsce (18.08.2026) — patrz komentarz
    /// przy `WorldGlobeView.place(for:)`. Puste dla miejsc "surowych" z
    /// samych zdjęć Memories, bez żadnego przystanku (30.08.2026).
    let trips: [SavedTrip]
}

private struct GlobePlaceMarker: View {
    let place: GlobePlace
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            } else {
                Text(CityGeocoder.flagEmoji(countryCode: place.countryCode))
                    .font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .shadow(radius: 3)
        .task(id: place.representativePhotoIdentifier) {
            guard let identifier = place.representativePhotoIdentifier else { return }
            thumbnail = await MediaAssetLoader.markerThumbnail(forAssetLocalIdentifier: identifier)
        }
    }
}
