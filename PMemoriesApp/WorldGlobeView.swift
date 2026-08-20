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
struct WorldGlobeView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
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
    /// Show Route), więc jeden, uniwersalny dialog zamiast osobnego alertu.
    @State private var actionPlace: GlobePlace?
    /// Drugi dialog — wybór KTÓREJ podróży pokazać trasę, gdy miejsce
    /// odwiedzone w ramach więcej niż jednej (user: "co jeśli jesteśmy w tym
    /// miejscu 2 raz albo przejazdem").
    @State private var tripPickerPlace: GlobePlace?
    @State private var routeOverviewTrip: SavedTrip?

    /// Grupowanie po ODLEGŁOŚCI (ten sam promień 20km i wzorzec co
    /// `SmartRouteDetector`), NIE po dokładnej nazwie — user zgłosił 30.07:
    /// lotnisko przylotu ("Milan–Malpensa Airport") i centrum miasta z
    /// odrębnych zdjęć ("Milan") to dwa RÓŻNE `SavedStop` (różne nazwy z
    /// geokodowania), ale to w oczach usera JEDNO odwiedzone miejsce — bez
    /// grupowania po odległości dostawały dwie osobne, nakładające się
    /// pinezki. W obrębie jednego klastra wygrywa stop z powiązanym filmem
    /// (jeśli jakiś ma), potem z miniaturką, potem pierwszy znaleziony —
    /// żeby scalenie nie "gubiło" ręcznie ustawionego powiązania.
    private var places: [GlobePlace] {
        let allStops = savedTrips.flatMap(\.stops).filter { $0.latitude != 0 || $0.longitude != 0 }
        return Self.clusterByProximity(allStops).compactMap(Self.place(for:))
    }

    private static let clusterRadiusKm: Double = 20

    private static func clusterByProximity(_ stops: [SavedStop]) -> [[SavedStop]] {
        var clusters: [[SavedStop]] = []
        for stop in stops {
            let matchIndex = clusters.firstIndex { cluster in
                cluster.contains { RouteProvider.straightDistanceKm(from: $0.coordinate, to: stop.coordinate) <= clusterRadiusKm }
            }
            if let matchIndex {
                clusters[matchIndex].append(stop)
            } else {
                clusters.append([stop])
            }
        }
        return clusters
    }

    private static func representative(of cluster: [SavedStop]) -> SavedStop? {
        cluster.first(where: { $0.linkedProjectID != nil })
            ?? cluster.first(where: { $0.representativePhotoIdentifier != nil })
            ?? cluster.first
    }

    /// Jedno miejsce (klaster) może mieć WIĘCEJ NIŻ JEDEN powiązany film —
    /// user 30.07.2026: np. dwie osobne wizyty w tym samym mieście, każda z
    /// innym filmem. `select(_:)` pokazuje wybór po nazwie zamiast po cichu
    /// skakać do pierwszego znalezionego.
    private static func place(for cluster: [SavedStop]) -> GlobePlace? {
        guard let representative = representative(of: cluster) else { return nil }
        var linkedProjectIDs: [UUID] = []
        for stop in cluster {
            if let id = stop.linkedProjectID, !linkedProjectIDs.contains(id) {
                linkedProjectIDs.append(id)
            }
        }
        // Podróże przechodzące przez to miejsce (18.08.2026, "Show Route" z
        // menu po tapnięciu) — ten sam duch deduplikacji co `linkedProjectIDs`
        // wyżej, tylko po `SavedTrip` zamiast po Memory. Klaster (grupowanie
        // po odległości) już dziś naturalnie łapie "byłem tu 2 razy"/
        // "przejazdem" — kilka `SavedStop` z RÓŻNYCH `SavedTrip` w jednym
        // miejscu, dokładnie przypadek który user opisał.
        var trips: [SavedTrip] = []
        for stop in cluster {
            if let trip = stop.trip, !trips.contains(where: { $0.id == trip.id }) {
                trips.append(trip)
            }
        }
        return GlobePlace(
            // Bug znaleziony 03.08.2026 (przegląd kodu) — samo `cityName`
            // nie jest unikalne (Paryż we Francji vs. Paryż w Teksasie,
            // Cambridge UK vs. Cambridge MA) — dwa różne klastry mogłyby
            // dostać identyczne `id`, a `ForEach`/adnotacje wymagają
            // unikalności (ryzyko brakującej pinezki albo tapnięcia
            // otwierającego złe miejsce). Kod kraju dopisany do każdej
            // nazwy w kluczu wystarczająco odróżnia realne przypadki, bez
            // komplikowania pełnymi współrzędnymi.
            id: cluster.map { "\($0.cityName)-\($0.countryCode ?? "")" }.joined(separator: "|"),
            cityName: representative.cityName, countryCode: representative.countryCode,
            coordinate: representative.coordinate,
            representativePhotoIdentifier: representative.representativePhotoIdentifier,
            linkedProjectIDs: linkedProjectIDs,
            trips: trips
        )
    }

    var body: some View {
        Group {
            if places.isEmpty {
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
                // pinezkami.
                .onAppear {
                    guard !hasSetInitialCamera else { return }
                    hasSetInitialCamera = true
                    // BUG (01.08.2026, user: "flagi i znaczniki dopiero
                    // pokazują się jak poruszymy globus") — ustawienie
                    // `cameraPosition` WPROST (bez animacji) najwyraźniej
                    // nie wystarcza, żeby MapKit w ogóle zbudował widoki
                    // adnotacji SwiftUI na widoku globusa (`.realistic`
                    // elevation) — dopiero PRAWDZIWY ruch kamery (gest usera
                    // albo animowana zmiana) uruchamia tę ścieżkę renderu.
                    // `withAnimation` zamiast gołego przypisania — to samo
                    // zdarzenie co animowany ruch, nie discrete state jump.
                    withAnimation(.easeInOut(duration: 0.6)) {
                        cameraPosition = .region(Self.initialRegion(for: places))
                    }
                }
                .onChange(of: selectedPlaceID) { _, newValue in
                    guard let newValue, let place = places.first(where: { $0.id == newValue }) else { return }
                    select(place)
                    selectedPlaceID = nil
                }
            }
        }
        .navigationTitle("Your Places")
        .navigationBarTitleDisplayMode(.inline)
        // Główny dialog po tapnięciu zdjęcia (18.08.2026) — "Go to Memory"
        // TYLKO gdy miejsce ma powiązany film (dawny warunek `guard` teraz
        // decyduje o WIDOCZNOŚCI przycisku, nie o osobnej ścieżce). "Show
        // Route" ZAWSZE dostępne — każdy klaster ma przynajmniej jedną
        // podróż z definicji (zbudowany z realnych `SavedStop`).
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
                Button(L("Show Route")) {
                    showRoute(for: place)
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
    /// przy `WorldGlobeView.place(for:)`.
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
