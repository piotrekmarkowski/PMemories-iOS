import SwiftUI
import MapKit
import SwiftData
import PhotosUI

/// Ekran budowy trasy podróży — user wpisuje miasta (z podpowiedziami miast
/// i lotnisk) i środek transportu między nimi, appka geokoduje i pokazuje
/// animowaną trasę na globusie. Udane trasy zapisywane trwale (`SavedTrip`,
/// SwiftData) — pierwszy krok fundamentu z `Docs/Database.md`, odblokowuje
/// możliwość odtworzenia dawnej podróży i prawdziwe statystyki na Home.
struct TravelMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedTrip.createdAt, order: .reverse) private var savedTrips: [SavedTrip]
    @Query(sort: \SavedProject.updatedAt, order: .reverse) private var projects: [SavedProject]
    @Binding var selectedTab: MainTab
    @Binding var pendingLibraryHighlightIDs: [UUID]
    /// Ustawiane z `HomeView` (tap na animowaną ikonkę globusa w karcie
    /// "Your Journey") — deep-link prosto do World Globe, z pominięciem
    /// głównego ekranu Travel Map. Ten sam wzorzec co `pendingLibraryHighlightIDs`.
    @Binding var pendingShowWorldGlobe: Bool
    /// Ustawiane z Trip Planning ("Convert Trip → Memory", 11.08.2026) —
    /// szkic trasy zbudowany z `PlannedTrip.asTripStops`, żeby user od razu
    /// widział gotowe przystanki zamiast wpisywać wszystko od nowa. Ten sam
    /// wzorzec co `pendingShowWorldGlobe` — jednorazowo skonsumowane w
    /// `init` (przez `_stops`), potem czyszczone w `.onAppear`, żeby
    /// zwykłe przejście na tę zakładkę później nie podchwyciło nieaktualnego
    /// szkicu.
    @Binding var pendingPrefillStops: [TripStop]?

    @State private var stops: [TripStop] = [TripStop(), TripStop()]
    @State private var isDetectingPeakForNewStop = false
    @State private var peakAddError: String?
    @State private var isShowingWorldGlobe = false
    @State private var isShowingAchievements = false
    @State private var linkingStopID: UUID?
    @State private var isShowingCancelConfirm = false
    /// Bug znaleziony 03.08.2026 (przegląd kodu) — "Edit" na zapisanej
    /// podróży z Trips (Badges, przeniesione tam tego samego dnia) wołał
    /// `startEditing(trip)` bezpośrednio, po cichu nadpisując cokolwiek
    /// user akurat wpisywał w formularz — bez pytania, w odróżnieniu od
    /// symetrycznego przycisku "Cancel" dwie linie niżej, który dla TEGO
    /// SAMEGO rodzaju nadpisania jawnie pyta przez `isShowingCancelConfirm`.
    /// Teraz Trips jest o dwa ekrany dalej niż formularz (wcześniej była
    /// to jedna sekcja na tym samym ekranie) — user częściej trafi tam z
    /// niedokończoną trasą w tle. Trzyma podróż "w kolejce" do wczytania,
    /// dopóki user nie potwierdzi (albo nie ma czego potwierdzać).
    @State private var pendingEditTrip: SavedTrip?
    @State private var isResolving = false
    @State private var resolveError: String?
    @State private var resolvedStops: [TripStop] = []
    @State private var isShowingAnimation = false
    @State private var speedMultiplier: Double = 1.0
    // Minimal White (31.07.2026) → Satellite (01.08.2026, user po
    // porównaniu ze starym nagraniem: "do tego możemy mieć satelitarną
    // mapę, lepiej wygląda") — dla lotów (stały, płaski dystans kamery
    // przez cały odcinek, patrz `TravelCinematics.frameState`) prawdziwe
    // zdjęcia satelitarne wyglądają dobrze, bo nie ma już kamery
    // pochylającej się/zbliżającej, która wcześniej uwidaczniała płaskie
    // oświetlenie/szarość.
    @State private var mapTheme: MapTheme = .satellite
    @State private var editingTripID: UUID?

    @State private var isShowingSmartRoutePicker = false
    @State private var smartRouteSelection: [PhotosPickerItem] = []
    @State private var isDetectingSmartRoute = false
    @State private var smartRouteError: String?
    @State private var isShowingSmartRouteReplaceConfirm = false

    init(
        selectedTab: Binding<MainTab>, pendingLibraryHighlightIDs: Binding<[UUID]>,
        pendingShowWorldGlobe: Binding<Bool>, pendingPrefillStops: Binding<[TripStop]?>
    ) {
        self._selectedTab = selectedTab
        self._pendingLibraryHighlightIDs = pendingLibraryHighlightIDs
        self._pendingShowWorldGlobe = pendingShowWorldGlobe
        self._pendingPrefillStops = pendingPrefillStops
        self._stops = State(initialValue: pendingPrefillStops.wrappedValue ?? [TripStop(), TripStop()])
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
        .onAppear {
            guard pendingPrefillStops != nil else { return }
            pendingPrefillStops = nil
        }
    }

    /// Wydzielone z poprzedniej wersji `body` po dodaniu Travel Achievements
    /// (30.07.2026) — dokładnie ten sam typ błędu type-checkera co przy
    /// `stopsList` niżej, w nowym miejscu (łańcuch modyfikatorów w `body`
    /// urósł zbyt duży po kolejnym `.navigationDestination`/toolbar
    /// przycisku). Rozwiązanie to samo: rozbicie na osobną właściwość.
    private var navigationContent: some View {
        stopsList
            // `List` maluje własne, nieprzezroczyste tło systemowe — bez
            // ukrycia go skórka zakładki (`.tabSkinBackground()`) byłaby
            // całkowicie zasłonięta (02.08.2026, skórki tła zakładek).
            .scrollContentBackground(.hidden)
            .tabSkinBackground()
            // BUG znaleziony 02.08.2026 (user: "'Travel Map' jest dalej
            // czarne") — `.toolbarColorScheme(_:for: .navigationBar)`
            // NIE steruje kolorem tekstu DUŻEGO tytułu nawigacji (tylko
            // materiał/przyciski) — sprawdzone bezpośrednio na urządzeniu,
            // nie zgadywane. Zamiast dalej walczyć z systemowym API,
            // dokładnie ten sam, już potwierdzony wzorzec co "Play
            // Memories" w `LibraryView`: WŁASNY tekst tytułu jako pierwszy
            // wiersz listy (`skinAwareHeading()`, pełna kontrola koloru),
            // zamiast `.navigationTitle`/systemowego dużego tytułu.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { travelMapToolbar }
            .onAppear {
                guard pendingShowWorldGlobe else { return }
                pendingShowWorldGlobe = false
                isShowingWorldGlobe = true
            }
            .navigationDestination(isPresented: $isShowingAnimation) {
                TravelMapAnimationView(stops: resolvedStops, speedMultiplier: speedMultiplier, mapTheme: mapTheme)
            }
            .navigationDestination(isPresented: $isShowingWorldGlobe) {
                WorldGlobeView(isPresented: $isShowingWorldGlobe, selectedTab: $selectedTab, pendingLibraryHighlightIDs: $pendingLibraryHighlightIDs)
            }
            .navigationDestination(isPresented: $isShowingAchievements) {
                AchievementsView(onEditTrip: { trip in
                    if hasUnsavedFormContent {
                        pendingEditTrip = trip
                    } else {
                        startEditing(trip)
                        isShowingAchievements = false
                    }
                })
            }
            .alert("Discard changes?", isPresented: $isShowingCancelConfirm) {
                    Button("Discard", role: .destructive) { cancelEditing() }
                    Button("Keep editing", role: .cancel) {}
                } message: {
                    Text("Unsaved changes (e.g. a linked video) will be lost.")
                }
                .alert("Discard changes?", isPresented: Binding(
                    get: { pendingEditTrip != nil },
                    set: { if !$0 { pendingEditTrip = nil } }
                )) {
                    Button("Discard", role: .destructive) {
                        if let pendingEditTrip {
                            startEditing(pendingEditTrip)
                        }
                        pendingEditTrip = nil
                        isShowingAchievements = false
                    }
                    Button("Keep editing", role: .cancel) { pendingEditTrip = nil }
                } message: {
                    Text("Editing this saved trip will replace the route you're currently building.")
                }
                .sheet(isPresented: Binding(
                    get: { linkingStopID != nil },
                    set: { if !$0 { linkingStopID = nil } }
                )) {
                    linkProjectSheet
                }
                .alert("Couldn't find all cities", isPresented: .init(
                    get: { resolveError != nil },
                    set: { if !$0 { resolveError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(resolveError ?? "")
                }
                .alert("Couldn't recognize the peak", isPresented: .init(
                    get: { peakAddError != nil },
                    set: { if !$0 { peakAddError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(peakAddError ?? "")
                }
                .alert("Replace current stops?", isPresented: $isShowingSmartRouteReplaceConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Replace") { isShowingSmartRoutePicker = true }
                } message: {
                    Text("The detected route will replace the current stops in the list.")
                }
                .alert("Couldn't detect a route", isPresented: .init(
                    get: { smartRouteError != nil },
                    set: { if !$0 { smartRouteError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(smartRouteError ?? "")
                }
                .photosPicker(
                    isPresented: $isShowingSmartRoutePicker,
                    selection: $smartRouteSelection,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                )
                .onChange(of: smartRouteSelection) { _, newSelection in
                    guard !newSelection.isEmpty else { return }
                    Task { await runSmartRouteDetection(newSelection) }
                }
    }

    // BUG znaleziony 04.08.2026 (user: "czasem jak wracam z library do
    // travel nie widzę ikonki globu i pucharu, ale nie zawsze tak się
    // dzieje") — `TravelMapView` jest tworzony OD NOWA za każdym
    // przełączeniem zakładki (`HomeView` renderuje go w `switch
    // selectedTab`, nie jako trwały `TabView`), a `if !savedTrips.isEmpty`
    // na świeżo utworzonym `@Query` bywa niedeterministycznie puste przez
    // jedną klatkę zanim zapytanie realnie się doładuje — stąd sporadyczne
    // migotanie. Oba ekrany docelowe (Achievements/World Globe) już mają
    // własne stany "brak podróży", więc bramkowanie tu było zbędne — teraz
    // przyciski są zawsze widoczne, zero wyścigu.
    @ToolbarContentBuilder
    private var travelMapToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingAchievements = true
            } label: {
                Image(systemName: "trophy")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingWorldGlobe = true
            } label: {
                Image(systemName: "globe.desk")
            }
        }
    }

    /// Wydzielone z `body` (osobna właściwość obliczana) — po dodaniu
    /// kolejnych funkcji dziś (Smart Route, World Globe, łączenie z filmem,
    /// potwierdzenie Anuluj) całe `body` jako jedno wyrażenie zaczęło
    /// przekraczać limit czasu type-checkera Swifta ("unable to type-check
    /// this expression in reasonable time" — REALNY błąd kompilacji,
    /// potwierdzony przez `xcodebuild`, nie fałszywy alarm SourceKit).
    /// Rozdzielenie samej zawartości `List` od łańcucha modyfikatorów w
    /// `body` to standardowy sposób obejścia tego ograniczenia.
    private var stopsList: some View {
        List {
            Text("Travel Map")
                // Zmniejszone z 34→26pt (11.08.2026, user: "napis mapa
                // podróży jest trochę za duży") — ten sam duch co
                // zmniejszenie powitania na Home 30.07.2026 (28→22pt).
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .skinAwareHeading()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            if let editingTripID, savedTrips.contains(where: { $0.id == editingTripID }) {
                Section {
                    EditingBanner(
                        isResolving: isResolving,
                        isSaveDisabled: stops.filter { !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }.count < 2,
                        onSave: { Task { await buildRoute(showAnimation: false) } },
                        onCancelTapped: { isShowingCancelConfirm = true }
                    )
                }
            }

            Section {
                // `ForEach($stops)` (tożsamość po `TripStop.id`, stałym
                // UUID), NIE po indeksie — indeks jako tożsamość (użyty tu
                // wcześniej dla przeciągania) powodował, że po zmianie
                // kolejności/wstawieniu na początku SwiftUI potrafiło
                // podmienić dane POD ISTNIEJĄCYM `@State` danego wiersza
                // (który picker otwarty itd.) zamiast stworzyć nowy — user
                // zgłosił migoczący, losowo się otwierający picker zdjęć
                // zamiast filmów po przeciąganiu/wstawianiu przystanków.
                // Przeciąganie identyfikuje wiersze przez `stop.id.uuidString`,
                // nie przez pozycję w tablicy.
                ForEach($stops) { $stop in
                    StopRow(stop: $stop, isFirst: stops.first?.id == stop.id, onLinkTapped: { linkingStopID = stop.id })
                        .draggable(stop.id.uuidString)
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            handleStopDrop(droppedIDs, ontoStopID: stop.id)
                        }
                }
                .onDelete { indices in
                    stops.remove(atOffsets: indices)
                }
            } footer: {
                Text("Enter cities in the order you visited them (airports work too). For each next stop, choose how you got there. Press and drag to reorder.")
                    .foregroundStyle(AppSkin.isAnySkinActive ? .white.opacity(0.85) : .secondary)
            }

            Section {
                Button {
                    stops.insert(TripStop(), at: 0)
                } label: {
                    Label("Add at start", systemImage: "arrow.up.circle")
                }
                Button {
                    stops.append(TripStop())
                } label: {
                    Label("Add at end", systemImage: "arrow.down.circle")
                }
                // Przeniesione tu z małej ikonki wewnątrz wiersza miasta
                // (01.08.2026, user: "tutaj jest mylące... ja bym to użył
                // zamiast wpisywania jako lokalizacja mojej pozycji") —
                // ta sama funkcja (GPS → najbliższy szczyt z OpenStreetMap
                // w promieniu 1km, `PeakDetector`), ale jako jasno opisany,
                // osobny przycisk zamiast niepodpisanej ikonki obok pola
                // tekstowego, gdzie łatwo ją pomylić z czymś innym.
                Button {
                    Task { await addPeakFromCurrentLocation() }
                } label: {
                    if isDetectingPeakForNewStop {
                        HStack {
                            ProgressView()
                            Text("Finding nearby peak…")
                        }
                    } else {
                        Label("Add peak from my location", systemImage: "location.viewfinder")
                    }
                }
                .disabled(isDetectingPeakForNewStop)
            }

            // Kolejność sekcji: Add at start/end → Show Route → Detect route
            // from photos — user 01.08.2026, prosta zmiana kolejności na
            // jego prośbę (dwie ścieżki budowania trasy, ręczna nad
            // automatyczną, obie nad ustawieniami animacji/mapy niżej).
            Section {
                BuildRouteButton(
                    isResolving: isResolving,
                    isEditing: editingTripID != nil,
                    isDisabled: stops.filter { !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }.count < 2 || isResolving,
                    onTap: { Task { await buildRoute() } }
                )
            }

            Section {
                Button {
                    if stops.contains(where: { !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        isShowingSmartRouteReplaceConfirm = true
                    } else {
                        isShowingSmartRoutePicker = true
                    }
                } label: {
                    if isDetectingSmartRoute {
                        Label("Detecting route…", systemImage: "sparkles")
                    } else {
                        Label("Detect route from photos", systemImage: "sparkles")
                    }
                }
                .disabled(isDetectingSmartRoute)
            } footer: {
                Text("The app detects places and order from your photos' location and date — review and adjust the result before saving.")
                    .foregroundStyle(AppSkin.isAnySkinActive ? .white.opacity(0.85) : .secondary)
            }

            Section {
                HStack {
                    Image(systemName: "hare")
                    Slider(value: $speedMultiplier, in: 0.5...3.0, step: 0.5)
                    Image(systemName: "tortoise")
                }
                Text(String(format: "%.1fx", speedMultiplier))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Animation Speed"))
                    .foregroundStyle(AppSkin.isAnySkinActive ? .white : .secondary)
            }

            Section {
                Picker("Map Theme", selection: $mapTheme) {
                    ForEach(MapTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(L("Map Theme"))
                    .foregroundStyle(AppSkin.isAnySkinActive ? .white : .secondary)
            }
        }
    }

    /// Wydzielone z `.sheet`'s trailing closure — ten sam powód co
    /// `stopsList`.
    private var linkProjectSheet: some View {
        NavigationStack {
            List {
                if let index = stops.firstIndex(where: { $0.id == linkingStopID }), stops[index].linkedProjectID != nil {
                    Button(role: .destructive) {
                        stops[index].linkedProjectID = nil
                        linkingStopID = nil
                    } label: {
                        Label("Unlink video", systemImage: "xmark.circle")
                    }
                }
                if projects.isEmpty {
                    Text("No saved projects in Studio/Library — create a movie first with \"Create Memory\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(projects) { project in
                    Button {
                        if let index = stops.firstIndex(where: { $0.id == linkingStopID }) {
                            stops[index].linkedProjectID = project.id
                        }
                        linkingStopID = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .foregroundStyle(.primary)
                                Text(project.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let index = stops.firstIndex(where: { $0.id == linkingStopID }), stops[index].linkedProjectID == project.id {
                                Image(systemName: "checkmark").foregroundStyle(Palette.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to a Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { linkingStopID = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Wywoływane po wyborze zdjęć w pickerze Smart Route — wyodrębnia
    /// identyfikatory assetów Photos (ten sam wymóg `photoLibrary: .shared()`
    /// co reszta pickerów w appce, inaczej `itemIdentifier` jest zawsze
    /// `nil`), oddaje resztę `SmartRouteDetector`.
    private func runSmartRouteDetection(_ selection: [PhotosPickerItem]) async {
        isDetectingSmartRoute = true
        defer { isDetectingSmartRoute = false }
        let identifiers = selection.compactMap(\.itemIdentifier)
        let detected = await SmartRouteDetector.detectStops(from: identifiers)
        smartRouteSelection = []
        guard !detected.isEmpty else {
            smartRouteError = "None of the selected photos have a saved location."
            return
        }
        stops = detected
    }

    /// GPS → najbliższy prawdziwy szczyt z OpenStreetMap (promień 1km),
    /// dodany jako NOWY, już rozwiązany przystanek na końcu listy —
    /// przeniesione z małej ikonki w wierszu miasta (patrz sekcja
    /// "Add at start/end" w `body`) na jasno opisany, osobny przycisk.
    private func addPeakFromCurrentLocation() async {
        isDetectingPeakForNewStop = true
        defer { isDetectingPeakForNewStop = false }
        do {
            let peak = try await PeakDetector.detectNearbyPeak()
            var stop = TripStop()
            stop.cityName = peak.name
            stop.coordinate = peak.coordinate
            stop.country = peak.country
            stop.countryCode = peak.countryCode
            stops.append(stop)
            MapTilePrefetcher.prefetch(coordinate: peak.coordinate)
        } catch {
            peakAddError = error.localizedDescription
        }
    }

    /// Przeciągnij-i-upuść zmiana kolejności przystanków — ten sam wzorzec
    /// (`.draggable`/`.dropDestination` na indeksie) co timeline w
    /// `EditView.moveItem`. User: przydaje się np. gdy Smart Route wykryło
    /// trasę bez lotu na początku — dodaje się go ręcznie i przeciąga na
    /// górę listy, zamiast wpisywać całą trasę od nowa.
    private func moveStop(from source: Int, to destination: Int) {
        guard stops.indices.contains(source), stops.indices.contains(destination) else { return }
        let moved = stops.remove(at: source)
        stops.insert(moved, at: destination)
    }

    /// Wydzielone z `.dropDestination`'s trailing closure — `TravelMapView.
    /// body` zaczęło przekraczać limit czasu type-checkera Swifta ("unable
    /// to type-check this expression in reasonable time" — ten sam,
    /// potwierdzony REALNY błąd kompilacji co wcześniej dziś w innych
    /// plikach), rozbicie na nazwaną funkcję to standardowy sposób obejścia.
    private func handleStopDrop(_ droppedIDs: [String], ontoStopID: UUID) -> Bool {
        guard let draggedIDString = droppedIDs.first,
              let draggedID = UUID(uuidString: draggedIDString),
              draggedID != ontoStopID,
              let draggedIndex = stops.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = stops.firstIndex(where: { $0.id == ontoStopID })
        else { return false }
        moveStop(from: draggedIndex, to: destinationIndex)
        return true
    }

    /// `showAnimation: false` używane przez szybki przycisk "Zapisz" na
    /// górze (przy edycji) — user 30.07.2026: "myślałem że dołączyłem tylko
    /// wideo do trasy" po tym jak zwykły zapis metadanych (np. powiązanie
    /// filmu) niespodziewanie odpalał całą animację podglądu. Sam zapis i
    /// pokazanie animacji to teraz dwie oddzielne decyzje, nie jeden pakiet.
    /// Jawny strażnik liczby przystanków TU (nie tylko przez `.disabled` na
    /// przycisku) — belt-and-suspenders przeciw crashowi `RenderError.
    /// notEnoughStops`, gdyby jakiś przycisk zapominał o blokadzie (dokładnie
    /// to się stało z nowym górnym przyciskiem "Zapisz").
    private func buildRoute(showAnimation: Bool = true) async {
        isResolving = true
        defer { isResolving = false }

        let namedStops = stops.filter { !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }
        guard namedStops.count >= 2 else {
            resolveError = "Add at least 2 named stops to save a route."
            return
        }
        var resolved: [TripStop] = []
        for stop in namedStops {
            // Jeśli user wybrał podpowiedź, współrzędne już są dokładne —
            // nie geokodować drugi raz.
            resolved.append(stop.isResolved ? stop : await CityGeocoder.resolve(stop))
        }

        let unresolved = resolved.filter { !$0.isResolved }
        guard unresolved.isEmpty else {
            resolveError = "Not found: " + unresolved.map(\.cityName).joined(separator: ", ")
            return
        }

        resolvedStops = resolved
        await persistTrip(resolved)
        if showAnimation {
            isShowingAnimation = true
        }
    }

    /// Zapisuje udaną trasę trwale — nową (`SavedTrip`) albo, jeśli
    /// `editingTripID` wskazuje istniejącą podróż, nadpisuje jej przystanki
    /// zamiast tworzyć duplikat. Dystans per odcinek liczony tu (ten sam
    /// `RouteProvider.route` co żywa animacja), żeby statystyki (`Travel.md`
    /// "Statystyki podróży") nie musiały go przeliczać na nowo za każdym
    /// razem, tylko czytać zapisaną wartość.
    private func persistTrip(_ resolved: [TripStop]) async {
        guard let first = resolved.first, let last = resolved.last else { return }
        let firstName = CityGeocoder.shortenedAirportName(first.cityName, coordinate: first.coordinate)
        let lastName = CityGeocoder.shortenedAirportName(last.cityName, coordinate: last.coordinate)
        let title = resolved.count >= 2 ? "\(firstName) → \(lastName)" : firstName
        var savedStops: [SavedStop] = []
        var previousCoordinate: CLLocationCoordinate2D?
        for (index, stop) in resolved.enumerated() {
            guard let coordinate = stop.coordinate else { continue }
            var legDistanceKm: Double = 0
            var elevationGainMeters: Double?
            var highestElevationMeters: Double?
            if let previousCoordinate {
                let result = await RouteProvider.route(from: previousCoordinate, to: coordinate, transport: stop.transport)
                legDistanceKm = result.distanceKm
                // Statystyki wysokości tylko dla Wędrówki — user: "pasuje
                // pokrycie na całym świecie łącznie z wysokościami, żeby mieć
                // też w statystykach jak wysoko się było" (29.07.2026).
                // `nil` przy błędzie zapytania (offline) zamiast przerywać
                // cały zapis trasy.
                if stop.transport == .hiking {
                    let profile = await ElevationProvider.profile(for: result.path)
                    elevationGainMeters = profile?.gainMeters
                    highestElevationMeters = profile?.highestMeters
                }
            }
            previousCoordinate = coordinate
            savedStops.append(SavedStop(
                cityName: stop.cityName, country: stop.country, countryCode: stop.countryCode,
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                transportRawValue: stop.transport.rawValue, order: index,
                arrivalDate: stop.arrivalDate, legDistanceKm: legDistanceKm,
                elevationGainMeters: elevationGainMeters, highestElevationMeters: highestElevationMeters,
                representativePhotoIdentifier: stop.representativePhotoIdentifier, linkedProjectID: stop.linkedProjectID
            ))
        }

        if let editingTripID, let existing = savedTrips.first(where: { $0.id == editingTripID }) {
            for oldStop in existing.stops { modelContext.delete(oldStop) }
            existing.stops = savedStops
            existing.title = title
            self.editingTripID = nil
        } else {
            modelContext.insert(SavedTrip(title: title, stops: savedStops))
        }

        // Jawny `save()` zamiast polegania wyłącznie na autosave —
        // zabezpieczenie na wypadek gdyby ekran został zniszczony/odtworzony
        // (np. przełączenie zakładki) zanim SwiftData samo odłoży zmiany na
        // dysk.
        try? modelContext.save()
    }

    /// Wczytuje przystanki zapisanej podróży z powrotem do edytowalnego
    /// formularza — user może dodać brakujące miejsca albo poprawić błąd,
    /// zamiast tworzyć duplikat od zera.
    private func startEditing(_ trip: SavedTrip) {
        let loadedStops = trip.asTripStops
        stops = loadedStops.isEmpty ? [TripStop(), TripStop()] : loadedStops
        editingTripID = trip.id
    }

    private func cancelEditing() {
        stops = [TripStop(), TripStop()]
        editingTripID = nil
    }

    /// Czy formularz ma coś warte ochrony przed cichym nadpisaniem — albo
    /// user już edytuje inną zapisaną podróż, albo wpisał ręcznie choć
    /// jedno miasto. Ten sam próg co reszta ekranu (`stops.filter { ... }`
    /// w kilku innych miejscach) — brak zaznaczonych, pustych pól to
    /// świeży, nietknięty formularz, nie ma czego bronić.
    private var hasUnsavedFormContent: Bool {
        editingTripID != nil || stops.contains { !$0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }
    }


}

/// Wydzielone z `TravelMapView.body` — cały baner z "Zapisz"/"Anuluj" jako
/// osobny typ, ten sam powód co reszta ekstrakcji w tym pliku dziś ("unable
/// to type-check this expression in reasonable time" po dodaniu kolejnych
/// funkcji — `TravelMapView.body` samo w sobie zrobiło się zbyt duże na
/// jedno wyrażenie dla type-checkera Swifta).
private struct EditingBanner: View {
    let isResolving: Bool
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onCancelTapped: () -> Void

    var body: some View {
        HStack {
            Label("Editing a saved trip", systemImage: "pencil.circle")
                .foregroundStyle(Palette.purple)
            Spacer()
            // "Zapisz" tu, NIE tylko na dole listy — user słusznie zauważył
            // 30.07.2026, że "Anuluj" na górze i jedyny przycisk zapisu na
            // dole (pod wszystkimi przystankami) to nielogiczny układ,
            // zwłaszcza przy dłuższej trasie wymagającej przewijania całego
            // ekranu tylko po to, żeby zapisać. Woła to samo `buildRoute()`
            // co przycisk na dole, ale z `showAnimation: false` — sam zapis,
            // bez wskakiwania w animację podglądu.
            //
            // Odstęp 24pt + wyraźnie stonowany styl "Anuluj" (szary, bez
            // wypełnienia) CELOWY — user tego samego dnia omyłkowo trafił w
            // "Anuluj" zamiast "Zapisz" (stały tuż obok siebie, oba zwykłym
            // tekstem, łatwo pomylić przy szybkim tapnięciu) — co
            // bezpowrotnie czyściło całą sesję edycji.
            if isResolving {
                ProgressView()
            } else {
                Button(action: onSave) {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Palette.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaveDisabled)
            }
            // Potwierdzenie PRZED skasowaniem sesji edycji — dodatkowa
            // warstwa bezpieczeństwa, zostaje mimo że prawdziwą przyczyną
            // (30.07.2026, potwierdzone logami: `onSave` i `onCancelTapped`
            // odpalały się OBA z jednego kliknięcia) był brak `.buttonStyle(
            // .plain)` na przyciskach w tym rzędzie `List` — bez tego stylu
            // SwiftUI potrafi "rozlać" jeden tap na kilka sąsiednich
            // przycisków w tym samym wierszu (ten sam mechanizm co wcześniej
            // dziś z ikonkami 📍🖼️🎞️ w `StopRow`).
            Button("Cancel", action: onCancelTapped)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
        }
    }
}

/// Wydzielone z `TravelMapView.body` — ten sam powód co `EditingBanner`.
private struct BuildRouteButton: View {
    let isResolving: Bool
    let isEditing: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if isResolving {
                Label("Looking up cities…", systemImage: "globe")
            } else if isEditing {
                Label("Save Changes", systemImage: "checkmark.circle")
            } else {
                Label("Show Route", systemImage: "map")
            }
        }
        .disabled(isDisabled)
    }
}

private struct StopRow: View {
    @Binding var stop: TripStop
    let isFirst: Bool
    /// Wywoływane po tapnięciu ikony filmu — otwieranie pickera trzyma
    /// RODZIC (`TravelMapView`, jeden wspólny `.sheet` na poziomie całego
    /// ekranu), nie ten wiersz. 30.07.2026: sheet prezentowany bezpośrednio
    /// z wnętrza wiersza `List` (jak było wcześniej) potrafił w rzadkich
    /// przypadkach gubić stan CAŁEJ listy przystanków po wyborze filmu (user
    /// zgłosił: po wybraniu filmu cała trasa wracała do pustego szablonu) —
    /// dokładnie ten sam, już sprawdzony wzorzec co Smart Route/World Globe
    /// (jeden `.sheet` na poziomie ekranu) eliminuje problem.
    let onLinkTapped: () -> Void
    @StateObject private var completer = CitySearchCompleter()
    @FocusState private var isFocused: Bool
    @State private var isApplyingSuggestion = false
    @State private var thumbnailImage: UIImage?
    @State private var isShowingPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(isFirst ? L("Starting city") : L("Next city"), text: $stop.cityName)
                    .focused($isFocused)
                    .onChange(of: stop.cityName) { _, newValue in
                        guard !isApplyingSuggestion else { return }
                        stop.coordinate = nil // zmiana tekstu ręcznie unieważnia wcześniej wybraną podpowiedź
                        completer.updateQuery(newValue)
                    }

                // Miniaturka na markerze mapy — ręczne przypisanie/zmiana
                // zdjęcia dla przystanków spoza Smart Route (tam wypełnia się
                // automatycznie z pierwszego chronologicznie zdjęcia klastra).
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    if let thumbnailImage {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    } else {
                        Image(systemName: "photo.circle")
                            .foregroundStyle(Palette.blue)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)

                // Ręczne powiązanie z gotowym filmem — napędza World Globe
                // (tap na miejsce → Library z tym projektem podświetlonym).
                // Zawsze RĘCZNE, nigdy zgadywane po dacie/nazwie (ten sam duch
                // co "Połącz z gotowym wideo" w Library dla starych projektów
                // bez zapisanego `exportedAssetIdentifier`).
                Button(action: onLinkTapped) {
                    Image(systemName: stop.linkedProjectID != nil ? "film.fill" : "film")
                        .foregroundStyle(Palette.blue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !stop.isResolved && !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completer.results.prefix(10).enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            select(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isFirst {
                Picker("Arrived by", selection: $stop.transport) {
                    ForEach(TransportMode.allCases) { mode in
                        Text("\(mode.emoji) \(mode.label)").tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            arrivalDateField
        }
        .padding(.vertical, 4)
        // Trzy prezentacje (zdjęcie/film/błąd szczytu) CELOWO na wspólnym,
        // stabilnym rodzicu (`VStack`), nie na pojedynczych, sąsiadujących
        // przyciskach — user zgłosił że kliknięcie ikony filmu otwierało
        // picker zdjęć zamiast listy filmów (znany kłopot SwiftUI: kilka
        // `.sheet`/`.photosPicker` na sąsiednich widokach w jednym rzędzie
        // potrafi się "pomylić" i odpalić prezentację sąsiada zamiast
        // własnej). Jeden wspólny rodzic eliminuje ten problem.
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $photoSelection, matching: .images, photoLibrary: .shared())
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            stop.representativePhotoIdentifier = newValue.itemIdentifier
            photoSelection = nil
        }
        .task(id: stop.representativePhotoIdentifier) {
            guard let identifier = stop.representativePhotoIdentifier else {
                thumbnailImage = nil
                return
            }
            thumbnailImage = await MediaAssetLoader.markerThumbnail(forAssetLocalIdentifier: identifier)
        }
    }

    /// Opcjonalna data pobytu — jeden tap żeby dodać, potem można poprawić.
    /// Celowo nieobowiązkowa, żeby nie dokładać tarcia do szybkiego
    /// wpisywania trasy (user: wybór środka transportu ma zajmować 2 sekundy).
    @ViewBuilder
    private var arrivalDateField: some View {
        if let date = stop.arrivalDate {
            HStack {
                // `.hourAndMinute` dodane 30.07.2026 (fundament "Cinematic
                // Lighting", `Travel.md`) — bez godziny nie da się policzyć
                // pozycji słońca nad horyzontem, tylko sam dzień. Domyślna
                // godzina (`Date()` przy pierwszym "Dodaj datę pobytu")
                // celowo NIE jest znacząca — user wpisuje realną godzinę
                // przylotu ręcznie, appka nigdy nie zgaduje.
                DatePicker(
                    "Arrival date and time",
                    selection: Binding(get: { date }, set: { stop.arrivalDate = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.caption)
                Button {
                    stop.arrivalDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                stop.arrivalDate = Date()
            } label: {
                Label("Add arrival date", systemImage: "calendar.badge.plus")
                    .font(.caption)
            }
        }
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        isApplyingSuggestion = true
        stop.cityName = suggestion.title
        isFocused = false
        completer.clear()
        Task {
            if let (coordinate, country, countryCode, localizedCityName) = await CitySearchCompleter.resolve(suggestion) {
                stop.coordinate = coordinate
                stop.country = country
                stop.countryCode = countryCode
                // Nadpisuje surowy tytuł podpowiedzi (w języku REGIONU
                // telefonu) nazwą w JĘZYKU APPKI, gdy geokodowanie się
                // powiedzie — patrz `CitySearchCompleter.resolve`.
                if let localizedCityName, !localizedCityName.isEmpty {
                    stop.cityName = localizedCityName
                }
                // Ściągnij kafelki dla tego miejsca W TLE od razu, zamiast
                // czekać aż user faktycznie odtworzy animację — user
                // 01.08.2026: "jak tylko ktoś zmieni skąd na dokąd, powinno
                // się już ściągać mapę". Fire-and-forget, nie blokuje UI.
                MapTilePrefetcher.prefetch(coordinate: coordinate)
            }
            isApplyingSuggestion = false
        }
    }
}

#Preview {
    TravelMapView(
        selectedTab: .constant(.travel), pendingLibraryHighlightIDs: .constant([]),
        pendingShowWorldGlobe: .constant(false), pendingPrefillStops: .constant(nil)
    )
}
