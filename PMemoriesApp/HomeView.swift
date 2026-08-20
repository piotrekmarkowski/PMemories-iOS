import SwiftUI
import PhotosUI
import SwiftData

/// Ekran startowy — "Dashboard": powitanie, duże CTA "Create Memory" (nie
/// "New Project" — user: "nie sprzedajesz projektu, sprzedajesz
/// wspomnienia"), i dwie sekcje-zajawki (Travel Intelligence, Recent
/// Memories). Odkąd `SavedTrip` (SwiftData) zapisuje podróże trwale, obie
/// sekcje pokazują PRAWDZIWE dane gdy istnieją — uczciwy stan pusty tylko
/// dopóki user nie zrobił jeszcze żadnej podróży.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    // Błysk na "Create Memory" za każdym otwarciem appki, nie tylko raz na
    // cały proces — user 01.08.2026: "powinien być za każdym razem jak
    // włączasz appkę". `scenePhase == .active` łapie zarówno "zimny start"
    // JAK I powrót z tła (user przełącza appki i wraca) — samo `.onAppear`
    // odpaliłoby się tylko raz, bo `HomeView` żyje przez cały czas życia
    // appki i nie jest tworzony od nowa przy powrocie na pierwszy plan.
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedTrip.createdAt, order: .reverse) private var savedTrips: [SavedTrip]
    @Query(sort: \SavedProject.updatedAt, order: .reverse) private var savedProjects: [SavedProject]
    @Query private var plannedTrips: [PlannedTrip]

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var isLoadingSelection = false
    @State private var loadingSelectionProgress: Double = 0
    @State private var isLoadingProject = false
    @State private var loadingProjectProgress: Double = 0
    @State private var editingItems: [MediaItem] = []
    @State private var editingProject: SavedProject?
    @State private var isShowingEdit = false
    @State private var isShowingProfile = false
    @State private var isShowingOnboarding = !OnboardingStorage.hasCompleted
    @State private var selectedTab: MainTab = .home
    /// Tablica, nie pojedynczy `UUID?` (04.08.2026) — miejsce na globusie
    /// może mieć kilka powiązanych filmów, wszystkie podświetlane naraz w
    /// Library zamiast wymuszać wybór jednego.
    @State private var pendingLibraryHighlightIDs: [UUID] = []
    @State private var pendingShowWorldGlobe = false
    @State private var isShowingOnThisDayPicker = false
    /// "Convert Trip → Memory" z Trip Planning (11.08.2026) — patrz komentarz
    /// przy `TravelMapView.pendingPrefillStops`.
    @State private var pendingTravelMapPrefillStops: [TripStop]?
    /// Indeks aktualnie pokazywanej statystyki w karcie "Your Journey" —
    /// TODO.md/UI.md 27.07.2026: "kafelek cyklicznie zmienia statystykę".
    @State private var journeyStatIndex = 0
    @State private var globeRotationDegrees: Double = 0
    @State private var avatarImage: UIImage? = AvatarStorage.load()
    /// Losowany raz na otwarcie appki — UI.md 27.07.2026: "zmiana TREŚCI
    /// powitania, nie tylko rozmiaru", żeby nie było zawsze tym samym
    /// zdaniem. Świadomie NIE rotuje W TRAKCIE patrzenia (jak kafelek
    /// statystyk) — powitanie to coś co user widzi raz przy wejściu, ciągła
    /// zmiana tekstu pod okiem byłaby rozpraszająca.
    @State private var greetingVariant = Int.random(in: 0..<3)
    /// Błysk na gwiazdce "✨" w "Create Memory" TYLKO przy otwarciu appki —
    /// UI.md 27.07.2026, poprawione 31.07.2026 (user: pierwsza wersja ze
    /// światłem przez cały przycisk była słaba, efekt ma być NA gwiazdce).
    @State private var starTwinkle = false
    @State private var hasPlayedStarTwinkle = false
    /// Import podróży wysłanej przez kogoś innego (11.08.2026, `.pmtrip`
    /// przez `.onOpenURL` — AirDrop/Wiadomości/Poczta), patrz `importTrip`.
    @State private var importedTripTitle: String?
    @State private var importTripError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .home: dashboardTab
                case .studio: studioTab
                case .travel: TravelMapView(
                    selectedTab: $selectedTab, pendingLibraryHighlightIDs: $pendingLibraryHighlightIDs,
                    pendingShowWorldGlobe: $pendingShowWorldGlobe, pendingPrefillStops: $pendingTravelMapPrefillStops
                )
                case .tripPlanning: TripPlanningView(selectedTab: $selectedTab, pendingTravelMapPrefillStops: $pendingTravelMapPrefillStops)
                case .library: LibraryView(
                    highlightedProjectIDs: $pendingLibraryHighlightIDs,
                    onOpenProject: { project in Task { await openProject(project) } }
                )
                }
            }
            .onChange(of: pickerSelection) { _, newSelection in
                guard !newSelection.isEmpty else { return }
                Task { await loadSelection(newSelection) }
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(selectedTab: $selectedTab)
            }
            .navigationDestination(isPresented: $isShowingEdit) {
                if let editingProject {
                    EditView(items: $editingItems, project: editingProject)
                }
            }
            .sheet(isPresented: $isShowingProfile, onDismiss: { avatarImage = AvatarStorage.load() }) {
                ProfileView()
            }
            .overlay {
                if isLoadingProject {
                    ProgressLabel(title: L("Loading photos…"), progress: loadingProjectProgress)
                }
            }
            .fullScreenCover(isPresented: $isShowingOnboarding) {
                OnboardingView { isShowingOnboarding = false }
            }
            .onOpenURL { url in
                importTrip(from: url)
            }
            .alert(L("Trip imported"), isPresented: Binding(
                get: { importedTripTitle != nil }, set: { if !$0 { importedTripTitle = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(String(format: L("\"%@\" was added to Trip Planning."), importedTripTitle ?? ""))
            }
            .alert(L("Couldn't import trip"), isPresented: Binding(
                get: { importTripError != nil }, set: { if !$0 { importTripError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(importTripError ?? "")
            }
        }
    }

    /// Odbiór podróży wysłanej przez kogoś innego — dwie drogi. Plik
    /// `.pmtrip` (11.08.2026, AirDrop/Wiadomości/Poczta) DZIAŁA OFFLINE,
    /// bez serwera. Universal Link (12.08.2026, user: "share ma przejść i
    /// się zapisywać w appce od razu w zaplanowanych, jak się otworzy
    /// link") — jedyny sposób który działa też z Messengera i podobnych
    /// appek, bo `apple-app-site-association` przechwytuje ten konkretny
    /// URL PRZED Safari, ale wymaga pobrania danych z `ShareLinkService`.
    /// Obie drogi zawsze tworzą NOWĄ, niezależną kopię (`PlannedTrip` bez
    /// `id` nadawcy) — świadomie brak scalania z istniejącymi podróżami.
    private func importTrip(from url: URL) {
        if url.pathExtension.lowercased() == "pmtrip" {
            importTripFromFile(url)
        } else if url.host == "pmemories.duckdns.org" || url.host == "piotrmarkowski.duckdns.org",
                  url.path.hasPrefix("/pmemories/trip/") {
            // Obie domeny akceptowane (13.08.2026) — nowa dedykowana
            // (`pmemories.duckdns.org`) dla przyszłych linków, stara
            // zostaje żeby wcześniej wysłane linki nadal działały.
            importTripFromLink(id: url.lastPathComponent)
        }
    }

    private func importTripFromFile(_ url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let dto = try TripTransferDTO.decode(from: data)
            // Plik `.pmtrip` działa offline, bez serwera — nie ma ID do
            // dowiązania, ta kopia zostaje jednorazowa (bez `shareID`).
            finishImportingTrip(dto, shareID: nil)
        } catch {
            importTripError = error.localizedDescription
        }
    }

    private func importTripFromLink(id: String) {
        Task {
            do {
                let dto = try await ShareLinkService.fetchTrip(id: id)
                // `shareID` = TO SAMO ID co u nadawcy (16.08.2026, żywa
                // synchronizacja) — od teraz obie strony mogą PUSHować
                // edycje i PULLować odświeżenie pod tym samym rekordem.
                finishImportingTrip(dto, shareID: id)
            } catch {
                importTripError = error.localizedDescription
            }
        }
    }

    private func finishImportingTrip(_ dto: TripTransferDTO, shareID: String?) {
        let trip = dto.makePlannedTrip()
        trip.shareID = shareID
        modelContext.insert(trip)
        importedTripTitle = trip.title.isEmpty ? L("Untitled trip") : trip.title
        selectedTab = .tripPlanning
        localizeImportedStopNames(trip)
    }

    /// Nazwy miast z importowanej podróży przychodzą w JĘZYKU NADAWCY (DTO
    /// niesie gotowy tekst, bez tłumaczenia po drodze) — user 13.08.2026:
    /// "jak ktoś mi wyśle zaproszenie, czy zapisze się w tym co mam na
    /// telefonie?". Dogeokodowanie W TLE, fire-and-forget, osobno per
    /// przystanek z rozwiązaną współrzędną — ten sam mechanizm co wybór
    /// miasta z podpowiedzi (`CitySearchCompleter.localizedCityName`). Zero
    /// blokowania importu — user widzi podróż od razu, nazwy "dogrywają
    /// się" w tle po chwili, w JEGO języku appki.
    private func localizeImportedStopNames(_ trip: PlannedTrip) {
        for stop in trip.stops ?? [] {
            guard let coordinate = stop.coordinate else { continue }
            Task {
                if let localizedName = await CitySearchCompleter.localizedCityName(for: coordinate), !localizedName.isEmpty {
                    stop.cityName = localizedName
                }
            }
        }
    }

    private var dashboardTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    // Ikonka appki (AppLogoMark, kopia realnego AppIcon) obok
                    // wordmarku zamiast samego tekstu — UI.md 27.07.2026.
                    Image("AppLogoMark")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    // "P" i "M" w kolorach z logo (Palette.blue → Palette.
                    // purple) — user 30.07.2026, ten sam zabieg co "Play
                    // Memories" w Library, tu wprost pierwsze dwie litery
                    // nazwy appki.
                    (Text("P").foregroundStyle(Palette.blue)
                     + Text("M").foregroundStyle(Palette.purple)
                     + Text("emories").foregroundStyle(AppSkin.isAnySkinActive ? .white : .primary))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .shadow(color: .black.opacity(AppSkin.isAnySkinActive ? 0.35 : 0), radius: 4, y: 1)
                    Spacer()
                    // Zdjęcie (jeśli user je ustawił w Profile) albo inicjał
                    // na gradiencie zamiast generycznego SF Symbol — UI.md
                    // 27.07.2026 + user 31.07.2026 "może w awatarze będzie
                    // można wstawić też swoje zdjęcie?" (`AvatarStorage`).
                    Button {
                        isShowingProfile = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            // Obwódka w gradiencie PM (01.08.2026, zewnętrzny
                            // feedback: "od razu wygląda bardziej premium") —
                            // tylko na prawdziwym zdjęciu, inicjał na gradiencie
                            // już MA kolor marki jako całe tło.
                            if let avatarImage {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 30, height: 30)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Palette.heroGradient, lineWidth: 1.5))
                            } else if let initial = AuthManager.shared.displayName?.first {
                                // BUG znaleziony 09.08.2026 — zahardcodowane "P"
                                // (ta sama klasa błędu co powitanie "Good
                                // afternoon, Piotr"), patrz `ProfileView.swift`.
                                Text(String(initial))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Palette.heroGradient, in: Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Palette.heroGradient, in: Circle())
                            }
                            // Odznaka testera (TODO.md 08.08.2026,
                            // `TesterRegistry`) — mała gwiazdka, bo cały
                            // awatar tu ma tylko 30pt, pełna odznaka jak w
                            // `ProfileView` by go zasłoniła.
                            if TesterRegistry.isTester(AuthManager.shared.userIdentifier) {
                                Image(systemName: "star.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white, Palette.purple)
                                    .background(Circle().fill(.white))
                                    .offset(x: 3, y: 3)
                            }
                        }
                    }
                }

                // Zmniejszone o ~20% (28→22) — user 27.07.2026: żeby CTA
                // "Create Memory" nie było spychane niżej.
                Text(greeting)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .skinAwareHeading()

                createMemoryCTA

                // Karta "Upcoming/current trip" (12.08.2026) — PRZED "On
                // This Day", bo patrzy w PRZÓD (aktualna/nadchodząca podróż)
                // zamiast wstecz, więc jest bardziej pilna. **Zawsze coś tu
                // jest** (user, drugi przebieg feedbacku: "Home zawsze ma
                // coś aktualnego... to jest mechanizm retencji") — realna
                // podróż gdy jest, inaczej zachęta do zaplanowania.
                if let featuredPlannedTrip {
                    UpcomingTripCard(
                        trip: featuredPlannedTrip,
                        onTap: { selectedTab = .tripPlanning },
                        onCreateMemory: { convertPlannedTrip(featuredPlannedTrip) }
                    )
                } else {
                    PlanTripPromptCard { selectedTab = .tripPlanning }
                }

                if !onThisDayMatches.isEmpty {
                    onThisDaySection
                }

                travelIntelligenceCard

                if !savedTrips.isEmpty {
                    lifetimeStatsSection
                }

                recentMemoriesSection
            }
            .padding(20)
        }
        .tabSkinBackground()
    }

    /// "Studio" na dolnym pasku — NIE świeży picker (to rola "Create
    /// Memory" na Home, jedynego głównego CTA). Od 30.07.2026 to prawdziwy
    /// ekran zamiast auto-otwierania najnowszego projektu wprost w edytorze:
    /// user chciał widzieć listę, nie zostać rzucony w edycję przy każdym
    /// tapnięciu zakładki. "Continue Editing" + reszta projektów + szybkie
    /// dodanie kolejnego.
    private var studioTab: some View {
        Group {
            if savedProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.heroGradient)
                    Text("Studio")
                        .font(.title3.bold())
                        .skinAwareHeading()
                    Text("Create a memory first with \"Create Memory\" — Studio will open it for further editing")
                        .font(.subheadline)
                        .skinAwareHeading()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        selectedTab = .home
                    } label: {
                        Text("Go to Create Memory")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Palette.heroGradient)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Studio")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .skinAwareHeading()

                        continueEditingCard

                        if !otherProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent Projects")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .skinAwareHeading()
                                VStack(spacing: 8) {
                                    ForEach(otherProjects) { project in
                                        StudioProjectRow(project: project) {
                                            Task { await openProject(project) }
                                        }
                                    }
                                }
                            }
                        }

                        PhotosPicker(
                            selection: $pickerSelection,
                            selectionBehavior: .ordered,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                Text("New Project")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
        }
        .tabSkinBackground()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = L("Good morning")
        case 12..<18: timeGreeting = L("Good afternoon")
        default: timeGreeting = L("Good evening")
        }
        switch greetingVariant {
        case 0:
            // BUG znaleziony 08.08.2026 (narzeczona usera zobaczyła "Good
            // afternoon, Piotr" na WŁASNYM telefonie) — imię było
            // zahardcodowane na sztywno, appka witała KAŻDEGO instalującego
            // ją usera imieniem developera. `AuthManager.displayName`
            // (Sign in with Apple, ustawiane przy logowaniu do Rankingu)
            // to jedyne miejsce gdzie appka w ogóle zna imię usera — gdy
            // user jeszcze się nie zalogował (Ranking jest opcjonalny),
            // zero zgadywania: powitanie bez imienia zamiast błędnej nazwy.
            if let name = AuthManager.shared.displayName {
                return "\(timeGreeting), \(name)"
            }
            return "\(timeGreeting)!"
        case 1: return L("Ready to create another memory?")
        default: return L("Where are we travelling today?")
        }
    }

    /// Najnowszy projekt, który NIE ma jeszcze wyeksportowanego filmu
    /// (`exportedAssetIdentifier == nil`) — user 30.07.2026: skończony
    /// projekt (np. już wyeksportowane Lanzarote) nie powinien wyglądać jak
    /// "do kontynuacji", nawet jeśli jest najnowszy na liście.
    private var continuableProject: SavedProject? {
        savedProjects.first(where: { $0.exportedAssetIdentifier == nil })
    }

    /// Reszta projektów pod "Continue Editing" na Studio — filtrowane po
    /// `id`, nie `dropFirst()`, bo `continuableProject` może wcale nie być
    /// pierwszym na liście (np. najnowszy jest już skończony).
    private var otherProjects: [SavedProject] {
        savedProjects.filter { $0.id != continuableProject?.id }
    }

    /// Prawdziwa karta "Continue Editing" — pokazuje ostatnio edytowany
    /// NIEUKOŃCZONY projekt (jeśli jakiś istnieje), zamiast fikcyjnego %
    /// postępu z mockupu: nie mamy sensownej definicji "ukończenia" filmu w
    /// sensie mierzalnego procentu, więc zamiast zmyślać liczbę pokazujemy
    /// uczciwe, realne fakty — liczbę klipów i kiedy ostatnio edytowane.
    @ViewBuilder
    private var continueEditingCard: some View {
        if let project = continuableProject {
            Button {
                Task { await openProject(project) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Palette.heroGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue Editing")
                            .font(.caption)
                        Text(project.title)
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(project.items.count) \(L("clips")) • \(project.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                    }
                    .skinAwareHeading()
                    Spacer()
                }
                .padding(16)
                .background(Palette.heroGradient.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// "Create Memory" buduje AUTOMATYCZNIE sensowną pierwszą wersję filmu
    /// (kolejność jak wybrana, Live Photo z ruchem domyślnie włączone) —
    /// user może potem wszystko zmienić ręcznie na ekranie Edit.
    private var createMemoryCTA: some View {
        PhotosPicker(
            selection: $pickerSelection,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            HStack(spacing: 8) {
                // Błysk TYLKO przy otwarciu appki — UI.md 27.07.2026, user
                // 31.07.2026: pierwsza wersja (światło przejeżdżające przez
                // CAŁY przycisk) była "słaba" — poprawka skupia efekt
                // wprost na gwiazdce zamiast na przycisku, dodatkowe dwa
                // mniejsze błyski dookoła dla efektu "twinkle".
                ZStack {
                    Text("✦").font(.system(size: 14)).opacity(starTwinkle ? 1 : 0)
                        .offset(x: -14, y: -10)
                    Text("✦").font(.system(size: 11)).opacity(starTwinkle ? 1 : 0)
                        .offset(x: 15, y: 8)
                    Text("✨")
                        .scaleEffect(starTwinkle ? 2.2 : 1.0)
                        .rotationEffect(.degrees(starTwinkle ? 20 : 0))
                        .shadow(color: .white.opacity(starTwinkle ? 1 : 0), radius: starTwinkle ? 16 : 0)
                }
                Text("Create Memory")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Palette.heroGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay {
            if isLoadingSelection {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.25))
                VStack(spacing: 6) {
                    ProgressView(value: loadingSelectionProgress).tint(.white).frame(width: 120)
                    Text("\(Int(loadingSelectionProgress * 100))%")
                        .font(.caption2).foregroundStyle(.white)
                }
            }
        }
        .onAppear { playStarTwinkle() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            playStarTwinkle()
        }
    }

    /// BUG naprawiony (01.08.2026, user: "dalej nie ma błysku") —
    /// `Animation.delay(...)` opóźnia WYŁĄCZNIE wizualną interpolację,
    /// samo przypisanie do `@State` wykonuje się natychmiast. Poprzednia
    /// wersja robiła OBA przypisania (`= true` i zaraz `= false`)
    /// SYNCHRONICZNIE, jedno po drugim, w tej samej chwili — więc
    /// `hasPlayedStarTwinkle` wracało do `false` od razu, zanim błysk
    /// realnie się pokazał. Gdy `.onAppear` i `.onChange(scenePhase)`
    /// trafiły blisko siebie (typowe przy starcie appki), drugie
    /// wywołanie nadpisywało/kasowało animację pierwszego, zanim user
    /// zdążył ją zobaczyć. Naprawa: prawdziwe opóźnienie przez
    /// `DispatchQueue.main.asyncAfter`, nie przez `Animation.delay`.
    private func playStarTwinkle() {
        guard !hasPlayedStarTwinkle else { return }
        hasPlayedStarTwinkle = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.4)) {
            starTwinkle = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                starTwinkle = false
            }
            hasPlayedStarTwinkle = false
        }
    }

    private var allCountryCodes: Set<String> {
        savedTrips.reduce(into: Set<String>()) { result, trip in result.formUnion(trip.countryCodes) }
    }

    private var totalTravelKm: Double {
        savedTrips.reduce(0) { $0 + $1.totalDistanceKm }
    }

    private var totalElevationGainMeters: Double {
        savedTrips.compactMap(\.totalElevationGainMeters).reduce(0, +)
    }

    /// Nazwa "Your Journey" zamiast pierwotnego "Travel Intelligence" — user
    /// 29.07.2026: brzmiało zbyt technicznie/korporacyjnie, zaproponował
    /// kilka alternatyw ("Your Journey", "Travel Insights", "Travel
    /// Summary"), nie zdecydował ostatecznie. Niskie ryzyko, łatwo odwracalna
    /// zmiana tekstu — wybieram najkrótszą z zaproponowanych zamiast dalej
    /// zwlekać.
    private var travelIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Journey")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .skinAwareHeading()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    // Osobny Button TYLKO dla ikonki — user 27.07.2026: "tap
                    // → mapa świata" (World Globe), inny cel niż reszta
                    // karty (Travel Map). Zagnieżdżanie Button w Button nie
                    // działa w SwiftUI, więc reszta rzędu dostaje zwykły
                    // `.onTapGesture` zamiast drugiego Button.
                    Button {
                        pendingShowWorldGlobe = true
                        selectedTab = .travel
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 26))
                            .foregroundStyle(Palette.heroGradient)
                            .rotationEffect(.degrees(globeRotationDegrees))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        if savedTrips.isEmpty {
                            Text("Start your first trip")
                                .font(.system(size: 15, weight: .semibold))
                                .skinAwareHeading()
                            Text("Your travel stats will appear here")
                                .font(.caption)
                                .skinAwareHeading()
                        } else {
                            // Rozmiary 15pt/caption → 19pt/11pt (01.08.2026,
                            // zewnętrzny feedback: "najważniejsza jest
                            // liczba") — wyraźniejsza hierarchia: statystyka
                            // jako główny element, "See your trips" jako
                            // ciche podpowiedzenie pod spodem.
                            Text(journeyStats[journeyStatIndex % journeyStats.count])
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .skinAwareHeading()
                                .contentTransition(.opacity)
                                .id(journeyStatIndex)
                            Text("See your trips")
                                .font(.system(size: 11))
                                .skinAwareHeading()
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedTab = .travel }

                // Km/przewyższenie pokazujemy tylko gdy mamy prawdziwe
                // dane (żadnych zer-jako-placeholderów) — ta sama zasada
                // "brak danych zamiast zmyślonej liczby" co przy
                // przewyższeniu na karcie podróży (TripPersistence.swift,
                // 30.07.2026).
                if totalTravelKm > 0 {
                    HStack(spacing: 20) {
                        statPill(icon: "arrow.left.and.right", value: "\(Int(totalTravelKm.rounded()).formatted()) km")
                        if totalElevationGainMeters > 0 {
                            statPill(icon: "mountain.2", value: "\(Int(totalElevationGainMeters.rounded()).formatted()) m")
                        }
                    }
                }
            }
            .padding(16)
            .background(Palette.heroGradient.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                globeRotationDegrees = 360
            }
        }
        .task {
            // Rotacja statystyk w karcie — UI.md 27.07.2026: "kraje→
            // miejsca→loty→km→km pieszo". Bez animacji przy pierwszym
            // pokazaniu (index 0 = domyślne Kraje•Podróże), dopiero kolejne
            // przełączenia się animują.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !journeyStats.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.4)) {
                    journeyStatIndex = (journeyStatIndex + 1) % journeyStats.count
                }
            }
        }
    }

    /// Statystyki do rotacji w karcie "Your Journey" — świadomie TYLKO
    /// prawdziwe, policzone dane (`TravelAchievementsCalculator`, ta sama
    /// funkcja co "Lifetime" niżej), zero wymyślonych kategorii jak
    /// "zdjęcia" z pierwotnej notatki UI.md — appka nie ma źródła danych na
    /// liczbę zdjęć per podróż, więc pomijamy zamiast zgadywać.
    private var journeyStats: [String] {
        let achievements = TravelAchievementsCalculator.achievements(from: savedTrips)
        func value(_ id: String) -> Double { achievements.first { $0.id == id }?.currentValue ?? 0 }

        var stats = ["\(allCountryCodes.count) \(countriesLabel(allCountryCodes.count)) • \(savedTrips.count) \(tripsLabel(savedTrips.count))"]
        let cities = value("cities")
        if cities > 0 { stats.append("\(Int(cities)) \(citiesLabel(Int(cities)))") }
        let flights = value("flights")
        if flights > 0 { stats.append("\(Int(flights)) \(flightsLabel(Int(flights)))") }
        if totalTravelKm > 0 { stats.append("\(Int(totalTravelKm.rounded()).formatted()) \(L("km travelled"))") }
        let hiking = value("hiking")
        if hiking > 0 { stats.append("\(Int(hiking).formatted()) km \(L("Hiking"))") }
        return stats
    }

    /// Polska ma TRZY formy liczby mnogiej (1 kraj / 2-4 kraje / 5+ krajów),
    /// nie dwie jak angielski — user 11.08.2026 zauważył "7 Kraje" zamiast
    /// poprawnego "7 Krajów" na karcie "Twoja podróż" (`L("Countries")`
    /// zawsze pokazywał tę samą formę, poprawną tylko dla 2-4). Naprawione
    /// TYLKO dla polskiego (`isPolishLanguageActive`/`polishPlural`,
    /// `LocalizedString.swift` — reużywane też w Trip Planning dla nocy/dni).
    private func countriesLabel(_ count: Int) -> String {
        guard isPolishLanguageActive else { return L("Countries") }
        return polishPlural(count, one: "Kraj", few: "Kraje", many: "Krajów")
    }

    private func tripsLabel(_ count: Int) -> String {
        guard isPolishLanguageActive else { return L("Trips") }
        return polishPlural(count, one: "Podróż", few: "Podróże", many: "Podróży")
    }

    /// Ten sam bug, druga runda (11.08.2026, user: "13 loty nie wygląda
    /// poprawnie") — "Cities"/"Flights" w tej samej karcie miały dokładnie
    /// tę samą, dotąd nienaprawioną wadę co "Countries"/"Trips".
    private func citiesLabel(_ count: Int) -> String {
        guard isPolishLanguageActive else { return L("Cities") }
        return polishPlural(count, one: "Miasto", few: "Miasta", many: "Miast")
    }

    private func flightsLabel(_ count: Int) -> String {
        // "Odbyty(e/ch)" dopisane 11.08.2026 (user: "teraz będzie 13 lotów
        // odbytych") — samo "Loty"/"Lotów" nie mówiło że to loty JUŻ
        // wykonane, nie np. planowane.
        guard isPolishLanguageActive else { return L("Flights") }
        return polishPlural(count, one: "Lot odbyty", few: "Loty odbyte", many: "Lotów odbytych")
    }

    /// "Lifetime" — user 30.07.2026: prosta lista każdej kategorii Travel
    /// Achievements (jedna pod drugą), NIE osobny rozbudowany ekran ze
    /// screenshot-worthy layoutem, o który prosił zewnętrzny feedback tego
    /// samego dnia — "nie bierz wszystkiego dosłownie". Ma być na pierwszej
    /// stronie (Home), zaraz pod kartą "Your Journey" — te same liczby co
    /// odznaki w Travel Map (`TravelAchievementsCalculator`), zero
    /// duplikowania logiki liczenia.
    private var lifetimeStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .skinAwareHeading()

            VStack(spacing: 0) {
                ForEach(Array(lifetimeRows.enumerated()), id: \.element.id) { index, row in
                    Group {
                        switch row {
                        case .simple(_, let emoji, let title, let value):
                            HStack(spacing: 10) {
                                Text(emoji)
                                Text(title)
                                    .font(.system(size: 15))
                                Spacer()
                                Text(value)
                                    .font(.system(size: 15, weight: .semibold))
                                    // `.opacity` → `.brightness` (02.08.2026, user:
                                    // "dalej sa za jasne") — przezroczystość na
                                    // JASNYM tle (zdjęcie) sprawia że kolor
                                    // PRZEŚWIETLA jaśniejszym pikselem pod spodem,
                                    // czyli wygląda JAŚNIEJ, nie ciemniej.
                                    // `.brightness()` realnie przyciemnia sam
                                    // renderowany kolor, niezależnie od tła pod spodem.
                                    .foregroundStyle(Palette.blue)
                                    .brightness(-0.25)
                            }
                        case .progressExplorer(let achievement, let title):
                            ExplorerProgressRow(achievement: achievement, title: title)
                        }
                    }
                    .skinAwareHeading()
                    .padding(.vertical, 8)
                    if index != lifetimeRows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private enum LifetimeRow: Identifiable {
        case simple(id: String, emoji: String, title: String, value: String)
        /// "Cities"/"Countries" gamifikowane (12/13.08.2026, user: "36 jest
        /// po prostu licznikiem... Cities Bronze, 14 cities until Silver",
        /// potem: "mamy linię na cities, a co z countries?") — TA SAMA
        /// odznaka/progi co ekran Badges (`TravelAchievementsCalculator`),
        /// zero duplikowania logiki poziomów, tylko inne miejsce pokazania.
        case progressExplorer(Achievement, title: String)

        var id: String {
            switch self {
            case .simple(let id, _, _, _): return id
            case .progressExplorer(let achievement, _): return achievement.id
            }
        }
    }

    /// Filtruje zera i pokazuje "Around the World" jako mnożnik (nie %,
    /// COFNIĘTE 12/13.08.2026 z powrotem do × — user: "100% brzmi jak coś
    /// ukończonego, 1.0× = zrobiłem jedno okrążenie, ile zrobię dalej?" —
    /// świadome odejście od zewnętrznego feedbacku z 01.08.2026 na rzecz
    /// własnej oceny usera, gamifikacja > czysta intuicyjność formatu).
    /// "ukrywałbym statystyki z wartością 0" (01.08.2026) zostaje bez zmian.
    private var lifetimeRows: [LifetimeRow] {
        let aroundTheWorld = TravelAchievementsCalculator.aroundTheWorld(from: savedTrips)
        var rows: [LifetimeRow] = []
        if aroundTheWorld.multiplier > 0 {
            rows.append(.simple(id: "aroundTheWorld", emoji: "🌍", title: L("Around the World"),
                                 value: String(format: "%.1f×", aroundTheWorld.multiplier)))
        }
        rows += TravelAchievementsCalculator.achievements(from: savedTrips)
            .filter { $0.currentValue > 0 }
            .map { achievement in
                switch achievement.id {
                case "cities": return .progressExplorer(achievement, title: L("City Explorer"))
                case "countries": return .progressExplorer(achievement, title: L("Country Explorer"))
                default: return .simple(id: achievement.id, emoji: achievement.emoji, title: achievement.title,
                                         value: achievement.formatted(achievement.currentValue))
                }
            }
        return rows
    }

    /// "Travel Time Machine" Faza 1 (`Travel.md`) — miejsca odwiedzone
    /// dokładnie tego samego dnia (miesiąc+dzień) w poprzednich latach.
    /// Powiadomienia push świadomie ODŁOŻONE (osobny temat: uprawnienia,
    /// harmonogram w tle) — na razie karta widoczna TYLKO gdy user sam
    /// otworzy appkę tego dnia, żadnego przypominania w tle.
    private var onThisDayMatches: [OnThisDayMatch] {
        TravelAchievementsCalculator.onThisDay(from: savedTrips)
    }

    /// "Ta jedna" podróż do pokazania na Home (12.08.2026) — trwająca ma
    /// pierwszeństwo przed nadchodzącą (jedno i drugie naraz raczej się nie
    /// zdarza, ale gdyby user miał dwie nachodzące na siebie podróże,
    /// "dzieje się teraz" jest ważniejsze niż "zbliża się"). Wśród
    /// nadchodzących — ta co zaczyna się NAJWCZEŚNIEJ. `nil` gdy żadna nie
    /// pasuje (appka wtedy nic tu nie pokazuje, zero zgadywania).
    private var featuredPlannedTrip: PlannedTrip? {
        if let inProgress = plannedTrips.first(where: \.isInProgress) {
            return inProgress
        }
        // "Welcome back" (niedawno zakończona) — DRUGI priorytet, przed
        // nadchodzącymi: user właśnie wrócił, to najbardziej aktualna rzecz.
        if let justCompleted = plannedTrips.filter(\.justCompleted)
            .max(by: { ($0.effectiveEndDate ?? .distantPast) < ($1.effectiveEndDate ?? .distantPast) }) {
            return justCompleted
        }
        return plannedTrips
            .filter { $0.daysUntilStart != nil }
            .min { ($0.effectiveStartDate ?? .distantFuture) < ($1.effectiveStartDate ?? .distantFuture) }
    }

    /// Zamiana zakończonej podróży w Memory wprost z Home (12.08.2026,
    /// karta "Welcome back") — ten sam mechanizm co `PlannedTripDetailView.
    /// convert()` w `TripPlanningView.swift` (nie da się go stamtąd
    /// bezpośrednio wywołać, to prywatna funkcja INNEGO widoku), więc
    /// świadomie zduplikowany, krótki kod zamiast przedwczesnej abstrakcji
    /// między dwoma miejscami.
    private func convertPlannedTrip(_ trip: PlannedTrip) {
        let prefill = trip.asTripStops
        pendingTravelMapPrefillStops = prefill
        modelContext.delete(trip)
        selectedTab = .travel
    }

    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On This Day")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .skinAwareHeading()
            VStack(spacing: 10) {
                ForEach(onThisDayMatches) { match in
                    OnThisDayCard(match: match) { handleOnThisDayTap(match) }
                }
            }
        }
        .photosPicker(
            isPresented: $isShowingOnThisDayPicker,
            selection: $pickerSelection,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
    }

    /// Film już istnieje dla tej podróży → prosto do niego w Library (ten
    /// sam mechanizm co World Globe). Filmu jeszcze nie ma → zwykły picker
    /// "Create Memory" (`pickerSelection` ma już `.onChange` wyżej, który
    /// odpala `loadSelection` — ta karta nie duplikuje tej logiki).
    private func handleOnThisDayTap(_ match: OnThisDayMatch) {
        guard match.linkedProjectIDs.isEmpty else {
            pendingLibraryHighlightIDs = match.linkedProjectIDs
            selectedTab = .library
            return
        }
        isShowingOnThisDayPicker = true
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .skinAwareHeading()
    }

    private var recentMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Memories")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .skinAwareHeading()

            if savedTrips.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("Your memories will appear here after creating your first movie")
                        .font(.caption)
                        .skinAwareHeading()
                    Spacer()
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(savedTrips.prefix(10)) { trip in
                            RecentMemoryTile(trip: trip)
                        }
                    }
                }
            }
        }
    }

    private func flagsForTrip(_ trip: SavedTrip) -> String {
        let codes = trip.countryCodes
        guard !codes.isEmpty else { return "🌍" }
        return codes.map { CityGeocoder.flagEmoji(countryCode: $0) }.joined()
    }

    /// Nowy projekt jest od razu zapisywany (`SavedProject`) — nie tylko
    /// trzymany w pamięci na czas edycji jak wcześniej.
    private func loadSelection(_ selection: [PhotosPickerItem]) async {
        // Bug znaleziony 03.08.2026 (przegląd kodu) — brak strażnika przed
        // ponownym wejściem: user mógł tapnąć w projekt na liście PODCZAS
        // gdy trwało już ładowanie (np. drugi picker albo drugi projekt),
        // co dawało dwa równoległe zapisy do tego samego `editingItems`/
        // `editingProject`/`isShowingEdit` — edytor mógł otworzyć się z
        // pomieszanymi danymi z obu ładowań.
        guard !isLoadingProject, !isLoadingSelection else { return }
        isLoadingSelection = true
        loadingSelectionProgress = 0
        defer { isLoadingSelection = false }
        // Ten sam problem co eksport (10.08.2026, user: "jak podczas
        // tworzenia filmu telefon zgaśnie") — ściąganie zdjęć/wideo z iCloud
        // (`MediaItemLoader.load`) może potrwać dłużej niż domyślny czas do
        // automatycznego wygaszenia ekranu. Dotąd tylko sam eksport
        // (`EditView.performExport`) miał tę blokadę — ładowanie PRZED
        // eksportem jej nie miało.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        editingItems = await MediaItemLoader.load(from: selection, onProgress: { progress in
            loadingSelectionProgress = progress
        })
        pickerSelection = []

        let newProject = SavedProject(title: "\(L("Memory")) \(Self.titleDateFormatter.string(from: Date()))")
        newProject.items = savedMediaItems(from: editingItems)
        modelContext.insert(newProject)
        editingProject = newProject

        isShowingEdit = true

        Task { await applyLocationBasedTitle(to: newProject) }
    }

    /// Nazwa projektu z miejsca zamiast samej daty, gdy wybrane zdjęcia mają
    /// GPS (user: "cel podróży zapisać" zamiast generycznego "Memory
    /// <data>"). Działa w tle PO wejściu do edytora — geokodowanie jest
    /// asynchroniczne (sieć) i nie ma sensu blokować na nim wejścia do
    /// edycji. Brak lokalizacji (screenshoty, brak GPS) po prostu zostawia
    /// oryginalny tytuł z datą, bez błędu.
    private func applyLocationBasedTitle(to project: SavedProject) async {
        let identifiers = project.items.map(\.assetLocalIdentifier)
        guard let location = MediaAssetLoader.firstLocation(forAssetLocalIdentifiers: identifiers),
              let city = await CityGeocoder.reverseResolve(location) else { return }
        project.title = "\(city), \(Self.titleDateFormatter.string(from: Date()))"
        try? modelContext.save()
    }

    private func openProject(_ project: SavedProject) async {
        // Ten sam strażnik co `loadSelection` wyżej — patrz komentarz tam.
        guard !isLoadingProject, !isLoadingSelection else { return }
        isLoadingProject = true
        loadingProjectProgress = 0
        defer { isLoadingProject = false }
        editingItems = await MediaAssetLoader.loadMediaItems(from: project.items, onProgress: { progress in
            loadingProjectProgress = progress
        })
        editingProject = project
        isShowingEdit = true
    }

    private func savedMediaItems(from items: [MediaItem]) -> [SavedMediaItem] {
        items.enumerated().compactMap { index, item in
            guard let identifier = item.pickerItemId else { return nil }
            return SavedMediaItem(
                assetLocalIdentifier: identifier, isLivePhoto: item.isLivePhoto, isVideo: item.isVideo,
                useMotion: item.useMotion, duration: item.duration, order: index
            )
        }
    }

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

enum MainTab {
    case home, studio, travel, tripPlanning, library
}

struct BottomTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack {
            TabBarButton(tab: .home, icon: "house.fill", title: L("Home"), selectedTab: $selectedTab)
            // Akcent koloru na Studio/Travel nawet gdy NIEwybrane — UI.md
            // 27.07.2026: "jako najważniejsze moduły", żeby wizualnie
            // wyróżniały się z paska zamiast wyglądać identycznie jak reszta
            // dopóki user w nie nie wejdzie.
            TabBarButton(tab: .studio, icon: "wand.and.stars", title: L("Studio"), selectedTab: $selectedTab, accentColor: Palette.purple)
            TabBarButton(tab: .travel, icon: "airplane", title: L("Travel"), selectedTab: $selectedTab, accentColor: Palette.blue)
            TabBarButton(tab: .tripPlanning, icon: "airplane.departure", title: L("Trip Planning"), selectedTab: $selectedTab)
            TabBarButton(tab: .library, icon: "photo.on.rectangle.angled", title: L("Library"), selectedTab: $selectedTab)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.regularMaterial)
    }
}

private struct TabBarButton: View {
    let tab: MainTab
    let icon: String
    let title: String
    @Binding var selectedTab: MainTab
    /// Kolor ikonki/tekstu gdy NIEwybrana (domyślnie `.secondary` jak
    /// dotąd) — patrz `BottomTabBar`.
    var accentColor: Color?

    var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Palette.blue : (accentColor?.opacity(0.75) ?? Color.secondary))
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OnThisDayCard: View {
    let match: OnThisDayMatch
    /// TODO.md 09.08.2026: karta była czysto informacyjna, brak akcji po
    /// tapnięciu. Gdy podróż ma już powiązany film (`linkedProjectIDs`,
    /// ustawiane ręcznie na World Globe) — przenosi do niego w Library
    /// zamiast udawać że "tworzy od nowa" nieistniejący wybór zdjęć (appka
    /// nie trzyma pełnej listy zdjęć per podróż, tylko jedno reprezentatywne
    /// per przystanek — patrz komentarz przy `RecentMemoryTile`). Gdy filmu
    /// jeszcze nie ma — otwiera zwykły picker "Create Memory", żeby user
    /// mógł od razu zacząć bez szukania przycisku niżej na ekranie.
    let onTap: () -> Void
    @State private var weather: TravelTimeMachineProvider.HistoricalWeather?

    private var yearsAgoText: String {
        match.yearsAgo == 1 ? L("1 year ago") : "\(match.yearsAgo) \(L("years ago"))"
    }

    private var actionLabel: String {
        match.linkedProjectIDs.isEmpty ? L("Create memory again") : L("Open memory")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(CityGeocoder.flagEmoji(countryCode: match.countryCode))
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(match.cityName) — \(yearsAgoText)")
                        .font(.system(size: 15, weight: .semibold))
                    Text(match.tripTitle)
                        .font(.caption)
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                Spacer()
                if let weather {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(weather.maxC.rounded()))°")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(Int(weather.minC.rounded()))°")
                            .font(.caption2)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .skinAwareHeading()
            .padding(14)
            .background(Palette.heroGradient.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .task {
            weather = await TravelTimeMachineProvider.historicalWeather(at: match.coordinate, date: match.visitDate)
        }
    }
}

/// Karta "co się dzieje z moją podróżą" (12.08.2026, user po rozbudowanej
/// dyskusji o Home jako "centrum całej podróży": "Planning → Travel →
/// Memories jednym systemem"). Ten sam styl co `OnThisDayCard` (gradient w
/// tle, flaga/emoji + dwie linie tekstu + akcja w `Palette.blue`,
/// `chevron.right`) — świadomie spójne z istniejącym wzorcem "dynamicznej
/// karty na Home", nie nowy język wizualny. DWA stany, `PlannedTrip.
/// isInProgress` decyduje które — trzeci stan ("nic zaplanowanego") appka
/// obsługuje przez PROSTE niepokazanie karty (`HomeView.dashboardTab`),
/// nie przez trzeci wariant tutaj.
private struct UpcomingTripCard: View {
    let trip: PlannedTrip
    let onTap: () -> Void
    /// Tylko dla stanu "Welcome back" — reszta stanów woła `onTap` (przejście
    /// do Trip Planning), ten jeden wprost konwertuje na Memory (user:
    /// "Po powrocie ... Create Memory"), więc dostaje osobny handler.
    let onCreateMemory: () -> Void

    /// Pięć stanów (12.08.2026, user po drugim przebiegu feedbacku, z
    /// dokładnym tekstem dla każdego) — sprawdzane w kolejności od
    /// najbardziej aktualnego: zakończona NIEDAWNO → w trakcie (w tym "dziś
    /// wylot") → nadchodząca. `isPlaceholder`/pusty stan appka obsługuje
    /// osobnym widokiem (`PlanTripPromptCard`), nie tutaj.
    fileprivate enum State: Equatable {
        case welcomeBack
        case startsToday
        case inProgress
        case tomorrow
        case upcoming(days: Int)
    }

    private var state: State {
        if trip.justCompleted { return .welcomeBack }
        if trip.daysUntilStart == 0 { return .startsToday }
        if trip.isInProgress { return .inProgress }
        if trip.daysUntilStart == 1 { return .tomorrow }
        if let days = trip.daysUntilStart { return .upcoming(days: days) }
        // Fallback teoretyczny — appka nie powinna tu trafić, bo
        // `HomeView.featuredPlannedTrip` już filtruje tylko pasujące podróże.
        return .inProgress
    }

    private var icon: String {
        switch state {
        case .welcomeBack: return "✨"
        case .inProgress: return "🌍"
        case .startsToday, .tomorrow, .upcoming: return "✈️"
        }
    }

    private var headline: String {
        switch state {
        case .welcomeBack:
            return L("Welcome back")
        case .startsToday:
            return L("Your trip starts today")
        case .tomorrow:
            return L("Tomorrow")
        case .upcoming(let days):
            return days == 1 ? L("1 day to go") : "\(days) \(L("days to go"))"
        case .inProgress:
            if let country = trip.currentStop?.country, !country.isEmpty {
                return String(format: L("You're in %@"), country)
            }
            if let day = trip.currentDayNumber, let total = trip.totalDayCount {
                return String(format: L("Day %d of %d"), day, total)
            }
            return trip.title
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Nazwa/tytuł + trasa razem, np. "Romania · London → Brașov" — ten sam
    /// fallback dla stanów nadchodzących i "dziś" (bez godziny), z osobną
    /// gałęzią gdy godzina odjazdu JEST znana.
    private var titleAndRoute: String {
        let title = trip.singleCountryName ?? (trip.title.isEmpty ? nil : trip.title)
        let route = trip.routeSummaryText
        switch (title, route) {
        case let (title?, route?): return "\(title) · \(route)"
        case let (title?, nil): return title
        case let (nil, route?): return route
        case (nil, nil): return L("New Trip")
        }
    }

    private var subheadline: String {
        switch state {
        case .welcomeBack:
            let name = trip.singleCountryName ?? trip.title
            if let total = trip.totalDayCount {
                let daysText = total == 1 ? L("1 day") : "\(total) \(L("days"))"
                return name.isEmpty ? daysText : "\(name) · \(daysText)"
            }
            return name
        case .startsToday:
            if let route = trip.routeSummaryText, let time = trip.departureTimeToday {
                return "\(route) · \(Self.timeFormatter.string(from: time))"
            }
            return trip.routeSummaryText ?? titleAndRoute
        case .tomorrow, .upcoming:
            return titleAndRoute
        case .inProgress:
            // Dzisiejsze miejsca do zobaczenia mają PIERWSZEŃSTWO (user,
            // pierwszy przebieg feedbacku: "dzień pokazuje co dzisiaj do
            // zobaczenia") — konkretniejsze i bardziej praktyczne niż sam
            // numer dnia/trasa, pokazywane gdy user faktycznie przypisał
            // miejsca do dziejszego dnia.
            let todayPlaces = trip.placesToVisitToday
            if !todayPlaces.isEmpty {
                let names = todayPlaces.prefix(2).map(\.name)
                let suffix = todayPlaces.count > 2 ? " +\(todayPlaces.count - 2)" : ""
                return "\(L("Today")): \(names.joined(separator: ", "))\(suffix)"
            }
            var parts: [String] = []
            if trip.currentStop?.country != nil, let day = trip.currentDayNumber, let total = trip.totalDayCount {
                parts.append(String(format: L("Day %d of %d"), day, total))
            }
            if let segment = trip.currentRouteSegmentText {
                parts.append(segment)
            }
            return parts.isEmpty ? trip.title : parts.joined(separator: " · ")
        }
    }

    private var actionLabel: String {
        state == .welcomeBack ? L("Create Memory") : L("View trip")
    }

    var body: some View {
        Button(action: state == .welcomeBack ? onCreateMemory : onTap) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subheadline)
                        .font(.caption)
                        .lineLimit(1)
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .skinAwareHeading()
            .padding(14)
            .background(Palette.heroGradient.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Wiersz "Cities"/"Countries" na Home, gamifikowany (12/13.08.2026, user:
/// "masz już poziomy Bronze/Silver/Gold, więc Home może pokazywać: City
/// Explorer, 36 cities, 14 cities to next level", potem: "a co z
/// countries?" — ta sama karta, ogólna). Reużywa `Achievement`'s gotowej
/// logiki progów (`progressToNext`/`progressMessage`, ten sam obiekt co
/// karta na ekranie Badges) — appka nie liczy tego drugi raz.
private struct ExplorerProgressRow: View {
    let achievement: Achievement
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(achievement.emoji)
                Text(title)
                    .font(.system(size: 15))
                Spacer()
                Text(achievement.formatted(achievement.currentValue))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                    .brightness(-0.25)
            }
            if achievement.nextMilestone != nil {
                ProgressView(value: achievement.progressToNext)
                    .tint(Palette.blue)
                if let message = achievement.progressMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let tierName = achievement.currentTierName {
                // Najwyższy poziom już zdobyty — bez pustego paska 100%,
                // sama nazwa poziomu wystarcza (ten sam duch co `Achievement.
                // progressMessage` == nil dla maxed odznak).
                Text(tierName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Pusty stan zamiast po prostu niepokazywania niczego (12.08.2026, user:
/// "Home zawsze ma coś aktualnego... to jest mechanizm retencji") — ten sam
/// wizualny wzorzec co `UpcomingTripCard`, zachęca zamiast informować.
private struct PlanTripPromptCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("🌍")
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Where are you travelling next?"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("Plan a trip"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .skinAwareHeading()
            .padding(14)
            .background(Palette.heroGradient.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Bogatszy kafelek "Recent Memories" — UI.md 27.07.2026: "flaga/kraj,
/// liczba dni, liczba zdjęć/wideo/filmów, tło = reprezentatywne zdjęcie".
/// Świadomie "liczba przystanków" zamiast "liczba zdjęć" — appka NIE ma
/// źródła danych na liczbę zdjęć per podróż (każdy `SavedStop` ma tylko
/// JEDNO reprezentatywne zdjęcie, nie pełny licznik), więc pokazywanie
/// wymyślonej liczby złamałoby zasadę "zero zgadywania" (ta sama zasada co
/// brak "100 Beaches" w Travel Achievements). Tło = zdjęcie pierwszego
/// przystanku z ustawionym `representativePhotoIdentifier`.
private struct RecentMemoryTile: View {
    let trip: SavedTrip
    @State private var thumbnail: UIImage?

    private var flags: String {
        let codes = trip.countryCodes
        guard !codes.isEmpty else { return "🌍" }
        return codes.map { CityGeocoder.flagEmoji(countryCode: $0) }.joined()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.15)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(flags)
                    .font(.system(size: 18))
                Text(trip.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let dayCount = trip.dayCount {
                        Label("\(dayCount)", systemImage: "calendar")
                    }
                    Label("\(trip.stops.count)", systemImage: "mappin.and.ellipse")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(8)
        }
        .frame(width: 130, height: 130)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            guard let identifier = trip.stops.first(where: { $0.representativePhotoIdentifier != nil })?.representativePhotoIdentifier else { return }
            thumbnail = await MediaAssetLoader.markerThumbnail(forAssetLocalIdentifier: identifier)
        }
    }
}

private struct StudioProjectRow: View {
    let project: SavedProject
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(project.items.count) \(L("clips")) • \(project.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .skinAwareHeading()
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension MainTab: Equatable {}

#Preview {
    HomeView()
}
