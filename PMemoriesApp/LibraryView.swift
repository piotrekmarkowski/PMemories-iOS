import SwiftUI
import SwiftData
import AVKit
import PhotosUI

/// Zakładka "Library" — prawdziwa lista zapisanych projektów (`SavedProject`,
/// SwiftData), zastępuje dawny placeholder "wkrótce". Tap na projekt
/// odtwarza jego media z biblioteki Photos (przez `MediaAssetLoader`) i
/// otwiera go w `EditView` — cały przepływ nawigacji trzyma `HomeView`
/// (jeden wspólny `NavigationStack`), ta lista tylko woła `onOpenProject`.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedProject.updatedAt, order: .reverse) private var projects: [SavedProject]
    /// Ustawiane przez World Globe (Travel Map) po tapnięciu połączonego
    /// miejsca — przewija do i podświetla wskazane projekty, potem czyści się
    /// samo (Binding, nie zwykła wartość), żeby ponowne wejście na Library
    /// bez nowego tapu na globusie nie podświetlało wciąż tych samych wierszy.
    /// Tablica, nie pojedynczy `UUID?` (04.08.2026) — jedno miejsce na
    /// globusie może mieć KILKA powiązanych filmów (kilka osobnych wizyt),
    /// user: zamiast zmuszać do wyboru jednego, podświetlamy WSZYSTKIE naraz.
    @Binding var highlightedProjectIDs: [UUID]
    let onOpenProject: (SavedProject) -> Void

    @State private var visuallyHighlightedIDs: Set<UUID> = []
    /// Prawdziwa data podróży (najwcześniejsza data zdjęcia w projekcie, nie
    /// data utworzenia/edycji w appce) — patrz `MediaAssetLoader.
    /// earliestCreationDate`. Cache per-projekt (`PHAsset.fetchAssets` jest
    /// lokalne/szybkie, ale nie ma sensu przeliczać przy KAŻDYM re-renderze
    /// widoku) — przeliczane tylko gdy zmieni się lista projektów.
    @State private var tripDates: [UUID: Date] = [:]

    /// Auto-nazwa z lokalizacji GPS (`HomeView.applyLocationBasedTitle`) nie
    /// zawsze trafia — user: sporo zdjęć nie ma lokalizacji zrobienia
    /// (wyłączona usługa lokalizacji) albo, przy przesyłaniu z telefonu na
    /// telefon w innym czasie/miejscu, może nieść lokalizację ZAPISU, nie
    /// zrobienia. Ręczna zmiana nazwy jako korekta/fallback.
    @State private var renamingProject: SavedProject?
    @State private var renameText: String = ""

    /// Ręczna korekta daty podróży (04.08.2026) — patrz `SavedProject.
    /// manualTripDate`. `editingDate` osobne od `editingDateProject != nil`
    /// jako warunek prezentacji sheetu, żeby `DatePicker` miał gdzie trzymać
    /// wybraną wartość PRZED zapisaniem (Cancel nie dotyka modelu).
    @State private var editingDateProject: SavedProject?
    @State private var editingDate: Date = Date()

    /// Skrót do gotowego filmiku — user: "żeby nie szukać w telefonie tych
    /// filmików, tylko włączać je z poziomu aplikacji". Appka nie trzyma
    /// samego pliku, tylko pobiera go na żądanie z biblioteki Photos po
    /// `SavedProject.exportedAssetIdentifier`.
    @State private var playingURL: URL?
    @State private var isLoadingPlayback = false
    @State private var playbackError: String?

    /// Stare projekty (sprzed wprowadzenia `exportedAssetIdentifier`) nie
    /// mają zapisanego skrótu — appka nie może się tego domyślić wstecz
    /// (nigdy tego nie zapisywała). Zamiast zmuszać usera do eksportu od
    /// zera, pozwalamy RĘCZNIE wskazać, który film w bibliotece to ten
    /// gotowy — jednorazowy wybór w pickerze zamiast ponownego tworzenia
    /// klipu.
    @State private var linkingProject: SavedProject?
    @State private var isLinkPickerPresented = false
    @State private var linkSelection: PhotosPickerItem?
    @State private var linkFeedback: String?

    /// Filtr kategorii (10.08.2026, `MemoryCategory`) — `nil` = pokaż
    /// wszystko, zachowanie sprzed tej funkcji.
    @State private var selectedCategoryFilter: MemoryCategory?

    var body: some View {
        Group {
            if projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.heroGradient)
                    // Zapomniane 07.08.2026 (user: "w każdym innym było
                    // zmienione") — jedyny tekst w tym pliku bez
                    // `.skinAwareHeading()`, więc na ciemnych/kolorowych
                    // skórkach zlewał się z tłem (domyślny `.primary` ledwo
                    // widoczny). Ten sam gotowy modyfikator (biały + cień)
                    // co reszta nagłówków w appce (`TabSkinBackground.swift`),
                    // zamiast ręcznie odtwarzać tę samą logikę.
                    VStack(spacing: 12) {
                        Text("Library")
                            .font(.title3.bold())
                        Text("Your projects will appear here after creating your first memory")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .skinAwareHeading()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                projectsList
            }
        }
        // `List` (`projectsList`) maluje własne, nieprzezroczyste tło
        // systemowe — bez ukrycia go skórka zakładki (`.tabSkinBackground()`)
        // byłaby całkowicie zasłonięta (02.08.2026, skórki tła zakładek).
        .scrollContentBackground(.hidden)
        .tabSkinBackground()
        .alert("Rename", isPresented: .init(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingProject = nil }
            Button("Save") { commitRename() }
        }
        // `DatePicker` nie mieści się w `.alert` (jak `Rename` wyżej) — stąd
        // `.sheet`, jedyny styl prezentacji tego wymagający.
        .sheet(isPresented: .init(
            get: { editingDateProject != nil },
            set: { if !$0 { editingDateProject = nil } }
        )) {
            NavigationStack {
                DatePicker("Trip Date", selection: $editingDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Edit Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editingDateProject = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { commitDateEdit() }
                        }
                    }
                    .presentationDetents([.medium])
            }
        }
        // `.fullScreenCover`, NIE `.sheet` — `.sheet` zawsze zostawia margines
        // od góry (widoczny pasek statusu: zegarek/zasięg/bateria), nawet z
        // `.ignoresSafeArea()` na samej zawartości, bo to ograniczenie stylu
        // prezentacji karty, nie czegoś do przykrycia od środka (user:
        // "widać te paski na górze, jakby czegoś brakowało do pełnego
        // ekranu"). `.fullScreenCover` faktycznie zajmuje cały ekran.
        .fullScreenCover(isPresented: .init(
            get: { playingURL != nil },
            set: { if !$0 { dismissPlayback() } }
        )) {
            if let playingURL {
                FullScreenVideoPlayer(url: playingURL) { dismissPlayback() }
            }
        }
        .alert("Playback failed", isPresented: .init(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
        // `isLinkPickerPresented` CELOWO osobne od `linkingProject` — gdy
        // oba były tym samym stanem (`isPresented: linkingProject != nil`),
        // wybranie pliku automatycznie zamykało sheet, co czyściło
        // `linkingProject` przez `set` TEGO SAMEGO bindingu — mogło wyścigowo
        // wyzerować `linkingProject` zanim `.onChange(of: linkSelection)`
        // zdążył go użyć, dając ciche "nic się nie dzieje" (user: "zrobiłem
        // z Italy... i nic się nie dzieje"). Teraz `linkingProject` jest
        // czyszczone WYŁĄCZNIE wewnątrz `onChange`, po realnym przetworzeniu.
        // `photoLibrary: .shared()` jest WYMAGANE żeby `PhotosPickerItem.
        // itemIdentifier` w ogóle nie było `nil` — domyślny, bezargumentowy
        // `.photosPicker` działa w trybie prywatności bez ujawniania
        // identyfikatora, niezależnie od nadanych appce uprawnień (potwierdzone
        // realnym alertem: "ten plik nie ma identyfikatora w bibliotece
        // Zdjęć" na KAŻDYM wybranym pliku, nie tylko szczególnym przypadku).
        .photosPicker(isPresented: $isLinkPickerPresented, selection: $linkSelection, matching: .videos, photoLibrary: .shared())
        .onChange(of: linkSelection) { _, newValue in
            guard let newValue else { return }
            guard let project = linkingProject else {
                linkFeedback = "Linking failed — try again."
                return
            }
            // `itemIdentifier` bywa `nil` dla plików bez pełnego dostępu do
            // biblioteki (np. ograniczony dostęp do Zdjęć) — jawny komunikat
            // zamiast cichego "nic się nie stało".
            guard let identifier = newValue.itemIdentifier else {
                linkFeedback = "This file has no identifier in your Photos library — try selecting another one."
                linkSelection = nil
                return
            }
            project.exportedAssetIdentifier = identifier
            try? modelContext.save()
            linkFeedback = "Linked \"\(project.title)\" to the selected video."
            linkingProject = nil
            linkSelection = nil
        }
        .alert("Video Link", isPresented: .init(
            get: { linkFeedback != nil },
            set: { if !$0 { linkFeedback = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkFeedback ?? "")
        }
    }

    /// Wydzielone z `body` — z `ScrollViewReader`/`.task` do przewijania i
    /// podświetlania projektu wskazanego przez World Globe, cały `body` w
    /// jednym wyrażeniu przekraczał limit czasu type-checkera Swifta
    /// ("unable to type-check this expression in reasonable time" — ten sam,
    /// potwierdzony REALNY błąd kompilacji co dziś wcześniej przy
    /// `LibraryView`'s odtwarzaczu pełnoekranowym, nie fałszywy alarm
    /// SourceKit).
    /// Data użyta do grupowania/wyświetlania — ręczna korekta (`manualTripDate`)
    /// wygrywa nad auto-wykrytą (`tripDates`, z metadanych zdjęć), która
    /// wygrywa nad `updatedAt` (fallback dopóki auto-wykrywanie się nie
    /// doliczy albo gdy zdjęcia nie mają w ogóle metadanych daty).
    private func effectiveTripDate(for project: SavedProject) -> Date {
        project.manualTripDate ?? tripDates[project.id] ?? project.updatedAt
    }

    /// Projekty pogrupowane wg roku PODRÓŻY — lata malejąco, w obrębie roku
    /// projekty najnowsze pierwsze (ten sam porządek co dotychczasowa
    /// płaska lista).
    private var groupedProjects: [(year: Int, projects: [SavedProject])] {
        let calendar = Calendar.current
        let filteredProjects: [SavedProject]
        if let selectedCategoryFilter {
            filteredProjects = projects.filter { $0.category == selectedCategoryFilter }
        } else {
            filteredProjects = projects
        }
        let withDates = filteredProjects.map { project in (project, effectiveTripDate(for: project)) }
        let grouped = Dictionary(grouping: withDates) { calendar.component(.year, from: $0.1) }
        return grouped.keys.sorted(by: >).map { year in
            let sorted = grouped[year]!.sorted { $0.1 > $1.1 }.map(\.0)
            return (year, sorted)
        }
    }

    /// Widoczny TYLKO gdy przynajmniej jeden projekt ma ustawioną kategorię
    /// — appka nie pokazuje pustego filtra userom którzy nie skorzystali z
    /// tej funkcji (ta sama zasada co reszta appki, żeby nie zaśmiecać UI
    /// czymś niepotrzebnym).
    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: L("All"), icon: nil, isSelected: selectedCategoryFilter == nil) {
                    selectedCategoryFilter = nil
                }
                ForEach(MemoryCategory.allCases) { category in
                    categoryChip(label: category.label, icon: category.icon, isSelected: selectedCategoryFilter == category) {
                        selectedCategoryFilter = selectedCategoryFilter == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryChip(label: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Palette.heroGradient : LinearGradient(colors: [Color.secondary.opacity(0.15)], startPoint: .top, endPoint: .bottom), in: Capsule())
            .foregroundStyle(isSelected ? .white : AppSkin.skinAwareTextColor())
        }
        .buttonStyle(.plain)
    }

    private func refreshTripDates() {
        for project in projects where tripDates[project.id] == nil {
            let identifiers = project.items.map(\.assetLocalIdentifier)
            tripDates[project.id] = MediaAssetLoader.earliestCreationDate(forAssetLocalIdentifiers: identifiers)
        }
    }

    private var projectsList: some View {
        ScrollViewReader { proxy in
                List {
                    // "P" i "M" w kolorach z logo (Palette.blue → Palette.purple,
                    // ten sam gradient co monogram PM w ikonce appki) — user
                    // 30.07.2026: nawiązanie do "PM" z nazwy PMemories, tylko
                    // pierwsze litery, reszta tekstu neutralna.
                    (Text("P").foregroundStyle(Palette.blue)
                     + Text("lay ").foregroundStyle(AppSkin.skinAwareTextColor())
                     + Text("M").foregroundStyle(Palette.purple)
                     + Text("emories").foregroundStyle(AppSkin.skinAwareTextColor()))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .shadow(color: .black.opacity(AppSkin.isAnySkinActive ? 0.35 : 0), radius: 4, y: 1)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                    if projects.contains(where: { $0.category != nil }) {
                        categoryFilterRow
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    }

                    ForEach(groupedProjects, id: \.year) { group in
                        Section {
                            yearSectionRows(group.projects)
                        } header: {
                            Text(String(group.year))
                                .foregroundStyle(AppSkin.skinAwareTextColor())
                        }
                    }
                }
                .task(id: projects.map(\.id)) { refreshTripDates() }
                .task {
                    guard !highlightedProjectIDs.isEmpty else { return }
                    let ids = highlightedProjectIDs
                    visuallyHighlightedIDs = Set(ids)
                    highlightedProjectIDs = []
                    // Bug znaleziony 04.08.2026 (crash log: "UICollectionView
                    // _validateScrollingTargetIndexPath... raisingException")
                    // — `scrollTo` wołane NATYCHMIAST na `.task` (jak dotąd,
                    // dla płaskiej listy działało, ale sekcje-po-latach
                    // dodają więcej pracy do pierwszego układu) potrafi
                    // trafić na moment ZANIM `List` zdążyła zbudować swoje
                    // wiersze — SwiftUI/UIKit rzuca wyjątek zamiast po cichu
                    // nic nie robić. Krótkie odczekanie daje pierwszemu
                    // układowi czas się skończyć, plus jawne sprawdzenie że
                    // cel w ogóle istnieje (np. nie został usunięty).
                    try? await Task.sleep(for: .milliseconds(150))
                    if let first = ids.first, projects.contains(where: { $0.id == first }) {
                        withAnimation { proxy.scrollTo(first, anchor: .center) }
                    }
                    // Podświetlenie NIE znika po timeoucie — user 04.08.2026:
                    // "niech zniknie dopiero jak klikniemy do otwierania albo
                    // jak po prostu wyjdziemy". Znika dopiero przy otwarciu
                    // projektu (`onOpenProject`/`play`, patrz `legacyProjectRow`)
                    // albo samo, bo cały widok (i jego `@State`) jest
                    // niszczony przy zmianie zakładki — `HomeView` renderuje
                    // `LibraryView` warunkowo w `switch selectedTab`, nie
                    // jako trwały `TabView`.
                }
        }
    }

    /// Wydzielone z `projectsList` — wiersze jednej sekcji (rok), ten sam
    /// zawartość co dawny płaski `ForEach(projects)`, tylko operujący na
    /// przekazanej pod-liście zamiast całej `projects`.
    @ViewBuilder
    private func yearSectionRows(_ sectionProjects: [SavedProject]) -> some View {
        ForEach(sectionProjects) { project in
            legacyProjectRow(project)
        }
        .onDelete { indices in
            for index in indices { modelContext.delete(sectionProjects[index]) }
        }
    }

    /// Zawartość jednego wiersza — wydzielona z dawnego płaskiego
    /// `ForEach(projects)` przy okazji grupowania po latach (`yearSectionRows`),
    /// bez zmiany samej zawartości.
    @ViewBuilder
    private func legacyProjectRow(_ project: SavedProject) -> some View {
        VStack(spacing: 0) {
        HStack {
                            Button {
                                visuallyHighlightedIDs = []
                                onOpenProject(project)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .foregroundStyle(.primary)
                                    // Data PODRÓŻY (ta sama co grupowanie po
                                    // latach), nie `updatedAt` — user ma
                                    // widzieć od razu jaka data "liczy się"
                                    // dla tego projektu, zanim zdecyduje czy
                                    // ją poprawić (patrz "Edit Date" niżej).
                                    HStack(spacing: 4) {
                                        Text("\(project.items.count) \(L("items")) • \(effectiveTripDate(for: project), style: .date)")
                                        if let category = project.category {
                                            Text("• \(category.label)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Osobny przycisk OBOK (nie wewnątrz) głównego —
                            // zagnieżdżony przycisk w środku Button/label nie
                            // dostaje własnego tapu w SwiftUI, cały wiersz
                            // złapałby `onOpenProject` zamiast odtwarzania.
                            if project.exportedAssetIdentifier != nil {
                                Button {
                                    Task { await play(project) }
                                } label: {
                                    if isLoadingPlayback {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(Palette.blue)
                                    }
                                }
                                .buttonStyle(.plain)
                                // `isLoadingPlayback` jest WSPÓLNE dla całej
                                // listy (nie per-wiersz) — bez tego user może
                                // odpalić kilka `play()` naraz (np. "połączyłem
                                // wszystkie 3 projekty, potem coś zaczęło się
                                // ładować i appka wyleciała" — potwierdzone
                                // crash logiem z telefonu: Jetsam,
                                // `reason: "per-process-limit"`, PMemories był
                                // największym procesem). Kilka równoległych
                                // kopiowań/pobrań dużych plików wideo z Photos
                                // (`PHAssetResourceManager`, zwłaszcza gdy
                                // materiał jest tylko w iCloud i trzeba go
                                // ściągnąć) wystarczająco podbija pamięć żeby
                                // system zabił appkę. Blokada drugiego tapu
                                // zanim pierwszy się skończy.
                                .disabled(isLoadingPlayback)
                            }
                        }
                        // Pasek W NORMALNYM UKŁADZIE (nie `.overlay`/
                        // `.listRowBackground`) — user 04.08.2026, po dwóch
                        // nieudanych próbach: `.overlay(bottom)` zostawiał
                        // przerwę do prawdziwej krawędzi wiersza,
                        // `.listRowBackground` źle liczył wysokość dla
                        // tytułów z dużo emoji (pasek lądował W ŚRODKU
                        // tekstu). Jako zwykły ostatni element `VStack`a
                        // pasek MUSI wylądować dokładnie pod treścią,
                        // niezależnie od tego ile miejsca ta treść zajmie.
                        if visuallyHighlightedIDs.contains(project.id) {
                            Rectangle()
                                .fill(Palette.heroGradient)
                                .frame(height: 3)
                                // Domyślny dolny margines wiersza (`.insetGrouped`
                                // List) zostaje POD paskiem — user 04.08.2026:
                                // "nie da się niżej na samym dole?". `.offset`
                                // (czysto wizualny przesunięcie, nie wpływa na
                                // rozmiar liczony przez `VStack`) zamiast
                                // zgadywania/nadpisywania systemowego
                                // `.listRowInsets` — dokładna wartość marginesu
                                // zależy od Dynamic Type, więc nadpisanie na
                                // sztywno mogłoby rozjechać zwykłe (niepodświetlone)
                                // wiersze.
                                .offset(y: 8)
                        }
                        }
                        .contextMenu {
                            Button {
                                startRenaming(project)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            // 04.08.2026, user: "dodajmy też opcję edycji
                            // daty, żeby w razie czego mógł ktoś poprawić" —
                            // auto-wykryta data podróży (z metadanych zdjęć)
                            // czasem się myli (zdjęcia bez metadanych, albo
                            // przesłane telefon-telefon z inną datą zapisu).
                            Button {
                                startEditingDate(project)
                            } label: {
                                Label("Edit Date", systemImage: "calendar")
                            }
                            // Kategorie Memory poza podróżami (10.08.2026,
                            // TODO.md 09.08) — `Menu` zagnieżdżone w
                            // `.contextMenu` renderuje się jako podmenu,
                            // ten sam wzorzec co reszta akcji tego wiersza.
                            Menu {
                                ForEach(MemoryCategory.allCases) { category in
                                    Button {
                                        project.category = category
                                        try? modelContext.save()
                                    } label: {
                                        Label(category.label, systemImage: category.icon)
                                    }
                                }
                                if project.category != nil {
                                    Button(role: .destructive) {
                                        project.category = nil
                                        try? modelContext.save()
                                    } label: {
                                        Label("Remove Category", systemImage: "xmark.circle")
                                    }
                                }
                            } label: {
                                Label("Set Category", systemImage: "tag")
                            }
                            // Zawsze dostępne, NIE tylko gdy brakuje
                            // identyfikatora od zera — user 30.07.2026: zapisany
                            // identyfikator może wskazywać na plik USUNIĘTY z
                            // biblioteki Zdjęć (`MediaAssetLoader.LoadError.
                            // assetNotFound` przy próbie odtworzenia), a wtedy
                            // dotychczasowy warunek CHOWAŁ jedyną drogę naprawy.
                            Button {
                                linkingProject = project
                                isLinkPickerPresented = true
                            } label: {
                                Label(
                                    project.exportedAssetIdentifier == nil ? "Link to finished video" : "Change linked file",
                                    systemImage: "link"
                                )
                            }
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Własne `.swipeActions(edge: .trailing)` NADPISUJE
                        // domyślne przesunięcie-do-usunięcia z `.onDelete`
                        // poniżej (user: "jak usunąć?" — zniknęło, gdy
                        // dodaliśmy tu samo "Zmień nazwę") — trzeba dopisać
                        // Usuń jawnie, obok zmiany nazwy.
                        .swipeActions(edge: .trailing) {
                            Button {
                                startRenaming(project)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Palette.purple)
                            Button {
                                startEditingDate(project)
                            } label: {
                                Label("Edit Date", systemImage: "calendar")
                            }
                            .tint(Palette.blue)
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
        .id(project.id)
    }

    private func play(_ project: SavedProject) async {
        guard let identifier = project.exportedAssetIdentifier else { return }
        visuallyHighlightedIDs = []
        isLoadingPlayback = true
        defer { isLoadingPlayback = false }
        // Wcześniej `try?` po cichu połykał błąd — user zgłosił "dalej nie
        // mogę odtworzyć" bez żadnego komunikatu, więc nie było jak
        // zdiagnozować przyczyny. Teraz realny błąd trafia do alertu.
        do {
            playingURL = try await MediaAssetLoader.videoURL(forAssetLocalIdentifier: identifier)
        } catch {
            playbackError = "\(error.localizedDescription) (identifier: \(identifier))"
        }
    }

    /// `MediaAssetLoader.videoURL` kopiuje CAŁE wideo z Photos do katalogu
    /// tymczasowego przy każdym odtworzeniu — bez sprzątania tu ta kopia
    /// zostawałaby na zawsze (04.08.2026, znalezione realnie na telefonie:
    /// 253 pliki, 11GB w `tmp`, patrz `TempFileCleanup`).
    private func dismissPlayback() {
        if let playingURL { try? FileManager.default.removeItem(at: playingURL) }
        playingURL = nil
    }

    private func startRenaming(_ project: SavedProject) {
        renameText = project.title
        renamingProject = project
    }

    private func commitRename() {
        guard let renamingProject else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            renamingProject.title = trimmed
            try? modelContext.save()
        }
        self.renamingProject = nil
    }

    private func startEditingDate(_ project: SavedProject) {
        editingDate = effectiveTripDate(for: project)
        editingDateProject = project
    }

    private func commitDateEdit() {
        guard let editingDateProject else { return }
        editingDateProject.manualTripDate = editingDate
        try? modelContext.save()
        self.editingDateProject = nil
    }
}

/// Odtwarzacz na cały ekran, wydzielony z `LibraryView.body` — trzymanie tego
/// w osobnym typie (nie inline w `.fullScreenCover`) rozbija złożoność
/// wyrażenia SwiftUI na mniejsze kawałki; wszystko w jednym `body` zaczęło
/// przekraczać limit czasu type-checkera Swifta ("unable to type-check this
/// expression in reasonable time" — realny błąd kompilacji, nie fałszywy
/// alarm SourceKit). `.fullScreenCover`, NIE `.sheet` — `.sheet` zawsze
/// zostawia margines od góry (widoczny pasek statusu), nawet z
/// `.ignoresSafeArea()` na zawartości, bo to ograniczenie stylu prezentacji
/// karty (user: "widać te paski na górze, jakby czegoś brakowało do pełnego
/// ekranu"). Własny przycisk zamknięcia, bo `.fullScreenCover` (w
/// przeciwieństwie do `.sheet`) nie ma domyślnego gestu zsuwania w dół.
private struct FullScreenVideoPlayer: View {
    let url: URL
    let onDismiss: () -> Void

    // Bug znaleziony 03.08.2026 (przegląd kodu) — `AVPlayer` był zwykłą
    // lokalną stałą w `body`, więc KAŻDY re-render tego widoku podczas
    // odtwarzania (np. zmiana Dynamic Type, albo dowolna zmiana w rodzicu
    // wywołana przez `@Query`) tworzył NOWY `AVPlayer` od zera, po cichu
    // resetując odtwarzanie do pauzy/pozycji 0. `@State` z domyślną
    // wartością tworzy się RAZ, przy pierwszym pojawieniu widoku.
    @State private var player: AVPlayer

    init(url: URL, onDismiss: @escaping () -> Void) {
        self.url = url
        self.onDismiss = onDismiss
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .onAppear {
            // `AVPlayer` nie odtwarza automatycznie po pojawieniu się w
            // `VideoPlayer` — user musiał dodatkowo kliknąć play w samym
            // odtwarzaczu. Kategoria sesji audio `.playback` (zamiast
            // domyślnej `.soloAmbient`) — bez tego dźwięk potrafi być
            // wyciszany przez fizyczny przełącznik cichy na telefonie
            // (user: "powinna lecieć załączona muzyka, a tego nie mamy" —
            // częsty gotcha z `AVPlayer` w sheet/VideoPlayer).
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
    }
}
