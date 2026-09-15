import SwiftUI
import PhotosUI
import MediaPlayer
import SwiftData
import UIKit
import AVFoundation
import os

/// Ekran edycji — podgląd, timeline (reorder + toggle ruchu Live Photo) i
/// dolny toolbar narzędzi, wzorowane na phone mockupie z moodboardu.
/// Wszystko co "+ Create Memory" zbudował automatycznie jest tu w pełni
/// edytowalne ręcznie: kolejność, ruch, muzyka, eksport.
///
/// `project` to zawsze już istniejący, wcześniej zapisany `SavedProject`
/// (tworzony przez wywołującego — `HomeView` przy nowym projekcie,
/// `LibraryView` przy otwarciu istniejącego) — `EditView` tylko synchronizuje
/// do niego zmiany stanu w kluczowych momentach, nie tworzy go samo.
struct EditView: View {
    @Binding var items: [MediaItem]
    let project: SavedProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// Dopasowanie do przystanku zaplanowanej podróży (30.08.2026) — patrz
    /// `TripMemoryMatcher`. Wszystkie zapisane podróże (nie tylko aktualnie
    /// oglądana) — dopasowanie po lokalizacji zdjęć, nie po tym, którą
    /// podróż user akurat przegląda.
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]
    @State private var tripMemorySuggestion: TripMemoryMatcher.Suggestion?

    @State private var selectedIndex = 0
    @State private var selectedSong: MPMediaItem?
    @State private var musicVolume: Double = 1.0
    @State private var isShowingMusicPicker = false
    @State private var isShowingAddMedia = false
    @State private var addMediaSelection: [PhotosPickerItem] = []
    @State private var isLoadingSelection = false
    @State private var loadingSelectionProgress: Double = 0
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var didExportSucceed = false
    /// Prawdziwy tester zgłosił "Export failed / Operation Stopped" po
    /// odpowiedzi na wiadomość w trakcie eksportu (10.08.2026) — potwierdzone
    /// w kodzie: `beginBackgroundTask` niżej daje appce tylko krótkie okno w
    /// tle, nie gwarancję. Zamiast pokazywać kryptyczny kod AVFoundation,
    /// appka pamięta czy zeszła z pierwszego planu W TRAKCIE eksportu i
    /// pokazuje wtedy zrozumiały komunikat zamiast surowego
    /// `error.localizedDescription`.
    @State private var wasBackgroundedDuringExport = false
    @State private var placeholderMessage: String?
    /// Które style przejść appka wolno wybrać przy auto-doborze (09.08.2026,
    /// user: "użytkownik sobie wybiera jakie przejścia chce i ile, program
    /// automatycznie sam je rozmieszcza") — patrz `StyleView`,
    /// `SavedProject.enabledTransitionStylesRaw`.
    /// Premium style (`.isPremium`) w domyślnej puli TYLKO dla Foundera
    /// (30.08.2026, `TesterRegistry.hasPremiumUnlocked`) — appka nie ma
    /// jeszcze systemu płatności dla reszty userów, patrz `StyleView`.
    @State private var enabledTransitions: Set<TransitionStyle> = Set(
        TransitionStyle.allCases.filter { !$0.isPremium || TesterRegistry.hasPremiumUnlocked(AuthManager.shared.userIdentifier) }
    )
    @State private var isShowingStyle = false
    /// Filtr kolorystyczny (09.08.2026) — patrz `StyleView`/`ColorGrader`.
    @State private var colorStyle: ColorStyle = .none
    /// "AI Director" (30.08.2026) — patrz `AIDirectorView`/`AIDirectorEngine`.
    @State private var isShowingAIDirector = false
    @State private var isShowingTrim = false
    @State private var isShowingPhotoDuration = false
    @State private var isShowingTotalDuration = false
    @State private var totalDurationInput: String = ""
    @State private var captions: [Caption] = []
    @State private var isShowingCaptions = false
    @State private var isShowingExportOptions = false
    @State private var exportQuality: ExportQuality = .hd1080
    /// Nakładki "picture-in-picture" — Faza 1 "prawdziwego multi-tracku"
    /// (patrz `Docs/Studio.md`). Osobny, mały tor NAD głównym timeline'em.
    @State private var overlays: [OverlayItem] = []
    @State private var isShowingAddOverlay = false
    @State private var overlayMediaSelection: [PhotosPickerItem] = []
    @State private var selectedOverlayIndex: Int?
    @State private var isShowingOverlaySettings = false

    // 14.09.2026 — `body` rozbite na trzy niezależnie sprawdzane
    // właściwości zamiast jednego, wciąż rosnącego łańcucha modyfikatorów.
    // Powód ten sam co przy `styleModifiers` (komentarz niżej) — na
    // GitHub Actions CI (wolniejszy/inny CPU niż lokalny Mac) skompilowanie
    // JEDNEGO `body` naprawdę padało: "the compiler is unable to type-check
    // this expression in reasonable time". Lokalnie budowało się bez
    // problemu, więc łatwo to przeoczyć — złapane dopiero przy pierwszym
    // realnym CI na tym pliku. Granica właściwości = granica
    // type-checkingu w Swifcie, stąd podział na `coreContent`/
    // `withSheetsAndPickers`/`body`, zero zmian w samej logice/zachowaniu.
    private var coreContent: some View {
        VStack(spacing: 0) {
            topBar
            preview
            timeline
            if !overlays.isEmpty {
                overlayRow
            }
            musicVolumeRow
            Spacer(minLength: 0)
            bottomToolbar
        }
        .navigationBarHidden(true)
        .task {
            loadInitialSong()
            overlays = await MediaAssetLoader.loadOverlayItems(from: project.overlays)
        }
        // Otwarcie edytora kopiuje CAŁE źródłowe wideo/Live Photo z Photos
        // do plików tymczasowych (`MediaAssetLoader.loadMediaItems`/
        // `loadOverlayItems`, per-item, przy KAŻDYM otwarciu) — bez
        // sprzątania te kopie zostawały na zawsze, realnie znalezione na
        // telefonie jako 253 pliki/11GB w `tmp` (04.08.2026, user: "apka ma
        // być lekka i nie ma zaśmiecać telefonu"). Skasować dopiero gdy
        // widok znika (koniec sesji edycji, plik już niepotrzebny) — NIE
        // wcześniej, bo `AVMutableComposition` czyta te pliki leniwie aż do
        // końca eksportu. `!isExporting` na wypadek cofnięcia się (swipe-back)
        // W TRAKCIE trwającego w tle eksportu — wtedy zostawiamy sprzątanie
        // najbliższej siatce bezpieczeństwa przy starcie appki
        // (`TempFileCleanup`) zamiast ryzykować skasowanie pliku, który
        // `AVAssetExportSession` właśnie aktywnie czyta.
        .onDisappear {
            guard !isExporting else { return }
            for item in items {
                if let url = item.videoURL { try? FileManager.default.removeItem(at: url) }
                if let url = item.pairedVideoURL { try? FileManager.default.removeItem(at: url) }
            }
            for overlay in overlays {
                if let url = overlay.videoURL { try? FileManager.default.removeItem(at: url) }
                if let url = overlay.pairedVideoURL { try? FileManager.default.removeItem(at: url) }
            }
        }
        .onChange(of: items.count) { _, _ in
            if selectedIndex >= items.count { selectedIndex = max(0, items.count - 1) }
            redistributeDurations()
            syncProject()
        }
        .onChange(of: selectedSong) { _, _ in
            redistributeDurations()
            syncProject()
        }
        .onChange(of: musicVolume) { _, _ in syncProject() }
        // Wydzielone do osobnej właściwości (`styleModifiers`), NIE dwa
        // kolejne modyfikatory wprost tutaj — całe `body` jako jedno
        // wyrażenie już wcześniej ocierało się o limit czasu type-checkera
        // Swifta (ten sam, już kilkukrotnie spotykany w tym pliku błąd
        // kompilacji), dwa kolejne dopisane 09.08.2026 go przekroczyły.
        .background(styleModifiers)
    }

    private var withSheetsAndPickers: some View {
        coreContent
        .onChange(of: captions) { _, _ in syncProject() }
        .sheet(isPresented: $isShowingCaptions) {
            CaptionsView(captions: $captions, totalDuration: items.reduce(0) { $0 + $1.duration })
        }
        .sheet(isPresented: $isShowingOverlaySettings) {
            if let selectedOverlayIndex, overlays.indices.contains(selectedOverlayIndex) {
                OverlaySettingsView(
                    overlay: $overlays[selectedOverlayIndex],
                    totalDuration: totalMainDuration,
                    otherOverlayRanges: overlays.indices.compactMap { index in
                        guard index != selectedOverlayIndex else { return nil }
                        let overlay = overlays[index]
                        return (start: overlay.globalStartTime, end: overlay.globalStartTime + overlay.duration)
                    },
                    onDelete: { deleteOverlay(at: selectedOverlayIndex) }
                )
            }
        }
        .sheet(isPresented: $isShowingExportOptions) {
            ExportOptionsView(quality: $exportQuality, onExport: {
                isShowingExportOptions = false
                Task { await performExport() }
            })
            .presentationDetents([.height(280)])
        }
        .onChange(of: addMediaSelection) { _, newSelection in
            guard !newSelection.isEmpty else { return }
            Task { await addMore(newSelection) }
        }
        // `photoLibrary: .shared()` wymagane żeby `PhotosPickerItem.
        // itemIdentifier` nie było `nil` (patrz `LibraryView.swift` po pełne
        // uzasadnienie, znalezione 30.07.2026 przy diagnozowaniu innego buga)
        // — bez tego `MediaItemLoader.pickerItemId` dla zdjęć DODANYCH w
        // trakcie edycji byłoby puste, więc po ponownym otwarciu projektu
        // `MediaAssetLoader` nie miałby jak ich odnaleźć. Główny picker
        // tworzący NOWY projekt (`HomeView.createMemoryCTA`) już to miał.
        .photosPicker(
            isPresented: $isShowingAddMedia,
            selection: $addMediaSelection,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: overlayMediaSelection) { _, newSelection in
            guard !newSelection.isEmpty else { return }
            Task { await addOverlay(newSelection) }
        }
        .photosPicker(
            isPresented: $isShowingAddOverlay,
            selection: $overlayMediaSelection,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .sheet(isPresented: $isShowingMusicPicker) {
            MusicPicker(
                onPick: { selectedSong = $0; isShowingMusicPicker = false },
                onCancel: { isShowingMusicPicker = false }
            )
            .ignoresSafeArea()
        }
    }

    var body: some View {
        withSheetsAndPickers
        .alert("Saved to camera roll", isPresented: $didExportSucceed) {
            Button("OK", role: .cancel) {}
        }
        // Dopasowanie do przystanku zaplanowanej podróży (30.08.2026) —
        // patrz `TripMemoryMatcher`/`checkTripMemoryMatch()`. Zawsze RĘCZNE
        // potwierdzenie (ten sam duch co "Link to a Movie" w `TravelMapView`)
        // — appka tylko PODPOWIADA, nigdy nie łączy po cichu.
        .alert(
            L("Link to your trip?"),
            isPresented: .init(
                get: { tripMemorySuggestion != nil },
                set: { if !$0 { tripMemorySuggestion = nil } }
            )
        ) {
            Button(L("Link")) {
                if let suggestion = tripMemorySuggestion {
                    suggestion.stop.linkedProjectID = project.id
                    try? modelContext.save()
                }
                tripMemorySuggestion = nil
            }
            Button(L("Not Now"), role: .cancel) { tripMemorySuggestion = nil }
        } message: {
            if let suggestion = tripMemorySuggestion {
                Text("\(L("This looks like it belongs to")) \(suggestion.trip.title) – \(suggestion.stop.cityName).")
            }
        }
        .alert("Export failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert(placeholderMessage ?? "", isPresented: .init(
            get: { placeholderMessage != nil },
            set: { if !$0 { placeholderMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .overlay {
            if isLoadingSelection {
                ProgressLabel(title: L("Loading photos…"), progress: loadingSelectionProgress)
            }
        }
        .background(exportBackgroundingWatcher)
        .sheet(isPresented: $isShowingTrim) {
            if items.indices.contains(selectedIndex) {
                TrimView(item: $items[selectedIndex], isFirst: selectedIndex == 0, onSplit: { splitTime in
                    splitSelectedItem(at: splitTime)
                })
            }
        }
        .sheet(isPresented: $isShowingPhotoDuration) {
            if items.indices.contains(selectedIndex) {
                PhotoDurationView(item: $items[selectedIndex], isFirst: selectedIndex == 0)
            }
        }
        .alert("Total Length", isPresented: $isShowingTotalDuration) {
            TextField("Seconds", text: $totalDurationInput)
                .keyboardType(.decimalPad)
            Button("Set") {
                if let seconds = Double(totalDurationInput.replacingOccurrences(of: ",", with: ".")), seconds > 0 {
                    redistributeDurations(targetTotal: seconds)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Splits this time evenly across all photos/clips that don't have a manually set duration.")
        }
    }

    /// `.onChange(of: scenePhase)` wydzielone z głównego `body` z tego
    /// samego powodu co `styleModifiers`/`overlayModifiers` niżej — dopisanie
    /// go wprost do łańcucha modyfikatorów w `body` przekroczyło limit czasu
    /// type-checkera Swifta ("unable to type-check this expression in
    /// reasonable time", 10.08.2026).
    @ViewBuilder
    private var exportBackgroundingWatcher: some View {
        Color.clear
            .onChange(of: scenePhase) { _, newPhase in
                if isExporting, newPhase != .active {
                    wasBackgroundedDuringExport = true
                }
            }
    }

    /// Wydzielone z `body` (patrz komentarz przy `.background(styleModifiers)`)
    /// — te dwa modyfikatory (Style/przejścia) osobno, żeby nie przekroczyć
    /// limitu czasu type-checkera Swifta w głównym `body`.
    @ViewBuilder
    private var styleModifiers: some View {
        Color.clear
            .onChange(of: enabledTransitions) { _, _ in syncProject() }
            .onChange(of: colorStyle) { _, _ in syncProject() }
            .sheet(isPresented: $isShowingStyle) {
                StyleView(enabledTransitions: $enabledTransitions, colorStyle: $colorStyle)
            }
            .sheet(isPresented: $isShowingAIDirector) {
                AIDirectorView(
                    items: $items, colorStyle: $colorStyle, enabledTransitions: $enabledTransitions,
                    selectedSong: $selectedSong
                ) {
                    syncProject()
                }
            }
    }

    /// Dzieli aktualnie zaznaczony klip na dwa niezależne kawałki tego
    /// samego źródła (ten sam `pickerItemId`, różne `trimStart`/`duration`)
    /// — obie połówki oznaczone jako ręcznie przycięte, żeby automatyczne
    /// rozłożenie czasu ich nie scaliło z powrotem.
    private func splitSelectedItem(at splitTime: Double) {
        guard items.indices.contains(selectedIndex) else { return }
        let source = items[selectedIndex]
        let start = source.trimStart
        let end = source.trimStart + source.duration
        guard splitTime > start + 0.1, splitTime < end - 0.1 else { return }

        var first = source
        first.duration = splitTime - start
        first.isManuallyTrimmed = true

        var second = source
        second.trimStart = splitTime
        second.duration = end - splitTime
        second.isManuallyTrimmed = true

        items.replaceSubrange(selectedIndex...selectedIndex, with: [first, second])
        syncProject()
    }

    /// Pełny Trim (suwak zakresu źródła) działa tylko na klipach z realnym
    /// źródłem wideo (wideo albo Live Photo z włączonym ruchem) — zwykłe
    /// zdjęcie nie ma czego przycinać w źródle. Zamiast pokazywać
    /// "niedostępne" (jak do 30.07.2026), zdjęcia dostają WŁASNY, prostszy
    /// arkusz (`PhotoDurationView`) — sam czas wyświetlania + obrót/kadrowanie,
    /// user: "ktoś będzie chciał kilka fotek... ustawianie długości
    /// wyświetlania każdego zdjęcia".
    private func openTrim() {
        guard items.indices.contains(selectedIndex) else { return }
        if items[selectedIndex].isTrimmable {
            isShowingTrim = true
        } else {
            isShowingPhotoDuration = true
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                syncProject()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
            }
            Spacer()
            Text("Edit")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
                isShowingExportOptions = true
            } label: {
                if isExporting {
                    Text("\(Int(exportProgress * 100))%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Palette.blue)
                        .clipShape(Capsule())
                } else {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Palette.blue)
                        .clipShape(Capsule())
                }
            }
            .disabled(items.isEmpty || isExporting)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var preview: some View {
        ZStack {
            Color.black
            if items.indices.contains(selectedIndex), let thumbnail = items[selectedIndex].thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if let overlay = currentOverlayForPreview, let thumbnail = overlay.thumbnail {
                GeometryReader { geo in
                    let boxWidth = geo.size.width * overlay.sizeScale
                    let boxHeight = boxWidth * (geo.size.height / geo.size.width)
                    let margin: CGFloat = 8
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: boxWidth, height: boxHeight)
                        .clipped()
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1))
                        .position(overlayPosition(corner: overlay.corner, boxWidth: boxWidth, boxHeight: boxHeight, margin: margin, in: geo.size))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipped()
    }

    /// Przybliżony podgląd nakładki PiP w statycznym preview — nie ma
    /// żywego odtwarzacza w tym ekranie (patrz `Docs/Studio.md`), więc to
    /// tylko orientacyjne, oparte o SUMĘ czasów klipów PRZED wybranym
    /// (`selectedIndex`), nie o dokładny czas z uwzględnieniem crossfade —
    /// świadome uproszczenie, aktualizuje się na żywo przy suwakach w
    /// `OverlaySettingsView` (ten sam `@Binding`).
    private var currentOverlayForPreview: OverlayItem? {
        let approxTime = items.prefix(selectedIndex).reduce(0.0) { $0 + $1.duration }
        return overlays.first { $0.globalStartTime <= approxTime && approxTime < $0.globalStartTime + $0.duration }
    }

    private func overlayPosition(corner: OverlayCorner, boxWidth: CGFloat, boxHeight: CGFloat, margin: CGFloat, in canvasSize: CGSize) -> CGPoint {
        switch corner {
        case .topLeading:
            return CGPoint(x: margin + boxWidth / 2, y: margin + boxHeight / 2)
        case .topTrailing:
            return CGPoint(x: canvasSize.width - margin - boxWidth / 2, y: margin + boxHeight / 2)
        case .bottomLeading:
            return CGPoint(x: margin + boxWidth / 2, y: canvasSize.height - margin - boxHeight / 2)
        case .bottomTrailing:
            return CGPoint(x: canvasSize.width - margin - boxWidth / 2, y: canvasSize.height - margin - boxHeight / 2)
        }
    }

    private var timeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    TimelineThumbnail(
                        item: $items[index],
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture { selectedIndex = index }
                    .draggable(String(index))
                    .dropDestination(for: String.self) { droppedIndices, _ in
                        guard let draggedIndexString = droppedIndices.first,
                              let draggedIndex = Int(draggedIndexString),
                              draggedIndex != index else { return false }
                        moveItem(from: draggedIndex, to: index)
                        return true
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteItem(at: index)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 82)
        .padding(.vertical, 10)
    }

    /// Osobny, mały wiersz NAD/pod głównym timeline'em, pokazujący nakładki
    /// PiP — Faza 1 "prawdziwego multi-tracku" (patrz `Docs/Studio.md`).
    /// Warunkowo widoczny (tylko gdy `overlays` nie jest puste), żeby
    /// projekty bez nakładek nie traciły miejsca na ekranie. BEZ drag-reorder
    /// — pozycja w czasie to jawna wartość (`globalStartTime`), nie kolejność
    /// w tablicy, więc przeciąganie nie miałoby tu sensu (retiming wyłącznie
    /// przez `OverlaySettingsView`).
    private var overlayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(overlays.indices, id: \.self) { index in
                    OverlayThumbnail(overlay: overlays[index])
                        .onTapGesture {
                            selectedOverlayIndex = index
                            isShowingOverlaySettings = true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteOverlay(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 60)
        .padding(.bottom, 6)
    }

    private var totalMainDuration: Double {
        items.reduce(0) { $0 + $1.duration }
    }

    private func deleteOverlay(at index: Int) {
        guard overlays.indices.contains(index) else { return }
        overlays.remove(at: index)
        if selectedOverlayIndex == index { selectedOverlayIndex = nil }
        syncProject()
    }

    /// Przeciągnij-i-upuść zmiana kolejności w timeline — pierwsza z dwóch
    /// zapowiedzianych funkcji "Multi-track + drag & drop" (prawdziwy
    /// multi-track z nakładającymi się warstwami to osobny, większy temat,
    /// patrz `Docs/Studio.md`).
    private func moveItem(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination) else { return }
        let movedItem = items.remove(at: source)
        items.insert(movedItem, at: destination)
        if selectedIndex == source {
            selectedIndex = destination
        }
        syncProject()
    }

    /// Usuwa pojedynczy klip z osi czasu (przytrzymaj → Usuń) — brakująca
    /// funkcja, timeline miała dotąd tylko reorder. `.onChange(of: items.count)`
    /// samo dociąga `selectedIndex` i przelicza `redistributeDurations()`
    /// (pozostałe zdjęcia rozciągają się na całą długość utworu).
    private func deleteItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        syncProject()
    }

    /// Poziom głośności muzyki w tle — osobny od głośności oryginalnego
    /// dźwięku klipów (`item.originalVolume`, kontrolowana w "Edit Clip").
    /// Widoczny tylko gdy jakiś utwór jest wybrany.
    @ViewBuilder
    private var musicVolumeRow: some View {
        if selectedSong != nil {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $musicVolume, in: 0...1)
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            ToolbarButton(icon: "photo.on.rectangle", title: L("Media")) {
                isShowingAddMedia = true
            }
            ToolbarButton(icon: "music.note", title: L("Music"), isActive: selectedSong != nil) {
                // 15.09.2026 — patrz `AnalyticsLogger`. Muzyka to jedna z
                // funkcji idących do Premium (`Pricing.md`, 15.09.2026: Free
                // to klipy pod social, bez wbudowanej ścieżki) — appka
                // dziś NIE blokuje jej jeszcze, więc to loguje ZAMIAR
                // (kto w ogóle sięga po muzykę), nie odbicie od blokady.
                AnalyticsLogger.log(.premiumFeatureTapped(feature: "music", source: "studio"))
                isShowingMusicPicker = true
            }
            ToolbarButton(icon: "paintpalette", title: L("Style"), isActive: colorStyle != .none) {
                isShowingStyle = true
            }
            ToolbarButton(icon: "sparkles", title: L("AI Director")) {
                isShowingAIDirector = true
            }
            ToolbarButton(icon: "textformat", title: L("Text"), isActive: !captions.isEmpty) {
                isShowingCaptions = true
            }
            ToolbarButton(icon: "scissors", title: L("Edit")) {
                openTrim()
            }
            ToolbarButton(icon: "timer", title: L("Length")) {
                totalDurationInput = String(format: "%.1f", items.reduce(0.0) { $0 + $1.duration })
                isShowingTotalDuration = true
            }
            ToolbarButton(icon: "pip", title: "PiP", isActive: !overlays.isEmpty) {
                // 15.09.2026 — patrz `AnalyticsLogger`, ten sam duch co
                // przycisk Music wyżej (loguje zamiar, appka jeszcze nie
                // blokuje).
                AnalyticsLogger.log(.premiumFeatureTapped(feature: "overlay_pip", source: "studio"))
                isShowingAddOverlay = true
            }
        }
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func addMore(_ selection: [PhotosPickerItem]) async {
        isLoadingSelection = true
        loadingSelectionProgress = 0
        defer { isLoadingSelection = false }
        // Patrz komentarz przy tej samej blokadzie w `HomeView.loadSelection`
        // (10.08.2026) — ściąganie z iCloud może potrwać, ekran nie powinien
        // zgasnąć w trakcie.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let newItems = await MediaItemLoader.load(from: selection, onProgress: { progress in
            loadingSelectionProgress = progress
        })
        items.append(contentsOf: newItems)
        addMediaSelection = []
    }

    /// Dodaje nową nakładkę PiP, domyślnie nad AKTUALNIE ZAZNACZONYM klipem
    /// (`selectedIndex`) — user 30.07.2026 słusznie zauważył, że wcześniejsza
    /// wersja zawsze doklejała nakładkę na sam początek/zaraz po poprzedniej,
    /// ignorując co jest zaznaczone w osi czasu ("zawsze będzie podpinany pod
    /// pierwsze co jest kompletnie bez sensu"). `desiredStart` to suma
    /// czasów klipów PRZED zaznaczonym — ten sam przybliżony wzorzec co
    /// `currentOverlayForPreview` używa do podglądu.
    private func addOverlay(_ selection: [PhotosPickerItem]) async {
        guard let picked = selection.first else { return }
        let loaded = await MediaItemLoader.load(from: [picked])
        guard let source = loaded.first else { return }
        let totalMainDuration = items.reduce(0.0) { $0 + $1.duration }
        let newDuration = min(3.0, max(0.5, totalMainDuration))
        let desiredStart = items.prefix(selectedIndex).reduce(0.0) { $0 + $1.duration }
        let existingRanges = overlays.map { (start: $0.globalStartTime, end: $0.globalStartTime + $0.duration) }
        let startTime = nextAvailableOverlayStart(
            desiredStart: desiredStart, duration: newDuration,
            totalDuration: totalMainDuration, existingRanges: existingRanges
        )
        overlays.append(OverlayItem(
            pickerItemId: source.pickerItemId, isLivePhoto: source.isLivePhoto, isVideo: source.isVideo,
            thumbnail: source.thumbnail, useMotion: source.useMotion,
            pairedVideoURL: source.pairedVideoURL, videoURL: source.videoURL,
            globalStartTime: startTime, duration: newDuration,
            corner: .bottomTrailing, sizeScale: 0.35
        ))
        overlayMediaSelection = []
        syncProject()
    }

    /// Szuka najbliższego WOLNEGO miejsca w czasie, zaczynając od
    /// `desiredStart`, przesuwając się w przód nad kolejnymi kolidującymi
    /// zakresami (Faza 1 zakazuje nakładkom nachodzenia na siebie NAWZAJEM —
    /// pojedynczy tor nakładki w eksporcie nie obsłuży dwóch pokrywających
    /// się zakresów, ten sam powód dla którego główny tor potrzebuje dwóch
    /// naprzemiennych torów A/B). Gdy zaznaczony klip koliduje z istniejącą
    /// nakładką, user i tak trafia w sensowne miejsce (zaraz PO kolizji), a
    /// nie z powrotem na początek filmu.
    private func nextAvailableOverlayStart(
        desiredStart: Double, duration: Double, totalDuration: Double,
        existingRanges: [(start: Double, end: Double)]
    ) -> Double {
        var candidate = max(0, min(desiredStart, max(0, totalDuration - duration)))
        for range in existingRanges.sorted(by: { $0.start < $1.start }) {
            if candidate + duration <= range.start { break }
            if candidate < range.end { candidate = range.end }
        }
        return min(candidate, max(0, totalDuration - duration))
    }

    /// Sklejenie do długości wybranego utworu — REALNEGO pliku audio, nie
    /// metadanych. ZNALEZIONY REALNY BUG 31.07.2026 (user: "piosenka się
    /// kończy a ostatnie zdjęcia dalej są pokazywane"): appka liczyła
    /// docelowy czas na podstawie `MPMediaItem.playbackDuration` (metadane
    /// z biblioteki Muzyki), ale do eksportu wstawiany jest dźwięk z
    /// `AVURLAsset(url: selectedSong.assetURL).duration` — PRAWDZIWY plik,
    /// przycięty w `VideoComposer` do `min(audioDuration, timelineEnd)`.
    /// Gdy metadane są dłuższe niż realny plik (rozbieżność w bibliotece
    /// Muzyki — zdarza się), obraz budowany jest pod dłuższy czas, a
    /// dźwięk i tak kończy się wcześniej. Naprawa: pobieramy PRAWDZIWY czas
    /// z tego samego źródła co eksport, zamiast metadanych.
    private func redistributeDurations() {
        Task { await redistributeDurationsToSelectedSong() }
    }

    private func redistributeDurationsToSelectedSong() async {
        guard let selectedSong else { return }
        let target = await realDuration(of: selectedSong)
        redistributeDurations(targetTotal: target)
        syncProject()
    }

    /// `assetURL` bywa `nil` (np. utwór tylko-w-chmurze niepobrany lokalnie)
    /// — wtedy fallback na metadane, lepsze przybliżenie niż nic.
    private func realDuration(of song: MPMediaItem) async -> Double {
        guard let url = song.assetURL else { return song.playbackDuration }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds,
              duration.isFinite, duration > 0 else {
            return song.playbackDuration
        }
        return duration
    }

    /// Proste sklejenie do ZADANEJ długości (utworu ALBO ręcznie wpisanej
    /// przez usera — "Długość całości" w toolbarze, 30.07.2026, dla kogoś
    /// kto składa tylko kilka zdjęć bez muzyki, np. pod social media) —
    /// dzieli czas równo na wszystkie elementy, POMIJAJĄC te ręcznie
    /// przycięte w Trim (`isManuallyTrimmed`) — ich czas zostaje taki, jaki
    /// user ustawił, a reszta dzieli między siebie to, co zostało.
    private func redistributeDurations(targetTotal: Double) {
        guard !items.isEmpty else { return }
        let autoIndices = items.indices.filter { !items[$0].isManuallyTrimmed }
        guard !autoIndices.isEmpty else { return }
        let manualTotal = items.indices.filter { items[$0].isManuallyTrimmed }
            .reduce(0.0) { $0 + items[$1].duration }
        // Rekompensata za crossfade — każde przejście MIĘDZY sąsiednimi
        // klipami NAKŁADA SIĘ na nie (nie dodaje czasu do filmu), więc bez
        // tej korekty suma `duration` równa długości utworu dałaby finalny,
        // wyeksportowany film KRÓTSZY o (liczba przejść) × czas przejścia —
        // user: "film zapisał mi się na 2:52" zamiast pełnych 3:19 utworu,
        // przy 67 klipach × 0.4s przejścia = 26.4s różnicy, dokładnie tyle
        // ile brakowało.
        let transitionOverlap = Double(max(0, items.count - 1)) * VideoComposer.transitionDuration.seconds
        let remaining = max(0, targetTotal + transitionOverlap - manualTotal)
        let perItem = remaining / Double(autoIndices.count)
        guard perItem.isFinite, perItem > 0 else { return }
        for index in autoIndices {
            items[index].duration = perItem
        }
    }

    /// 23.08.2026 — TRZECI raport tego samego bugu (`-11838`), teraz
    /// potwierdzone przez usera że powtarza się NIEZALEŻNIE od filtra Style i
    /// jakości eksportu — wyklucza to `ColorGrader` (pomijany bez filtra) i
    /// `canvasSize` jako jedyną przyczynę. Zamiast zgadywać CZWARTĄ z rzędu
    /// poprawkę bez pewności, oznaczamy KTÓRY etap zawiódł — przy kolejnym
    /// zgłoszeniu (jeśli błąd wróci) zrzut ekranu wskaże już konkretne
    /// miejsce zamiast tylko surowego kodu AVFoundation.
    private struct ExportStageError: Error {
        let stage: String
        let underlying: Error
    }

    /// Idzie w głąb `NSUnderlyingErrorKey` — `AVAssetExportSession` często
    /// chowa bardziej konkretną przyczynę (np. błąd konkretnego kodeka/
    /// zasobu) POD surowym `-11838`, którego samo domain/code nie ujawnia.
    /// Tester nie ma konsoli Xcode, więc to musi zmieścić się w jednym
    /// zrzucie ekranu z alertem.
    private func describeErrorChain(_ error: Error) -> String {
        var parts: [String] = []
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 5 {
            let nsError = err as NSError
            var part = "\(nsError.domain) \(nsError.code)"
            if let reason = nsError.localizedFailureReason {
                part += " (\(reason))"
            }
            parts.append(part)
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return parts.joined(separator: " ← ")
    }

    /// 24.08.2026 — patrz komentarz przy wywołaniu. `os.Logger` (nie `print`)
    /// — zwykły `print()` idzie na surowy stdout procesu i NIE trafia do
    /// zunifikowanego logowania systemowego, więc `idevicesyslog`/Console bez
    /// podłączonego Xcode go w ogóle nie widzi (odkryte dziś rano: pierwsza
    /// wersja tej funkcji z `print` nie zostawiła ŻADNEGO śladu mimo
    /// potwierdzonej awarii w tym samym momencie). `privacy: .public`
    /// wszędzie — domyślnie os_log ukrywa interpolowane wartości jako
    /// `<private>`, bez tego cała diagnostyka byłaby bezużyteczna.
    private static let exportDiagnosticsLogger = Logger(subsystem: "com.piotrmarkowski.pmemories", category: "ExportDiagnostics")

    private func logCompositionDiagnostics(_ project: VideoComposer.ComposedProject, items: [MediaItem]) {
        let composition = project.composition
        let log = Self.exportDiagnosticsLogger
        log.notice("🔍 EXPORT DIAGNOSTICS — items: \(items.count, privacy: .public)")
        for (index, item) in items.enumerated() {
            log.notice("🔍   [\(index, privacy: .public)] isVideo=\(item.isVideo, privacy: .public) isLivePhoto=\(item.isLivePhoto, privacy: .public) duration=\(item.duration, privacy: .public) mutesBackgroundMusic=\(item.mutesBackgroundMusic, privacy: .public) transitionStyle=\(String(describing: item.transitionStyle), privacy: .public)")
        }
        log.notice("🔍 composition.duration=\(composition.duration.seconds, privacy: .public)")
        log.notice("🔍 video tracks: \(composition.tracks(withMediaType: .video).count, privacy: .public)")
        for track in composition.tracks(withMediaType: .video) {
            let segments = track.segments.map { seg in
                "target[\(seg.timeMapping.target.start.seconds)..<\(seg.timeMapping.target.end.seconds)]"
            }.joined(separator: ", ")
            log.notice("🔍   videoTrack id=\(track.trackID, privacy: .public) segments=[\(segments, privacy: .public)]")
        }
        log.notice("🔍 audio tracks: \(composition.tracks(withMediaType: .audio).count, privacy: .public)")
        for track in composition.tracks(withMediaType: .audio) {
            let segments = track.segments.map { seg in
                "target[\(seg.timeMapping.target.start.seconds)..<\(seg.timeMapping.target.end.seconds)]"
            }.joined(separator: ", ")
            log.notice("🔍   audioTrack id=\(track.trackID, privacy: .public) segments=[\(segments, privacy: .public)]")
        }
        log.notice("🔍 videoComposition.renderSize=\(String(describing: project.videoComposition.renderSize), privacy: .public) frameDuration=\(project.videoComposition.frameDuration.seconds, privacy: .public)")
        log.notice("🔍 videoComposition.instructions: \(project.videoComposition.instructions.count, privacy: .public)")
        for (index, instruction) in project.videoComposition.instructions.enumerated() {
            guard let instruction = instruction as? AVVideoCompositionInstruction else { continue }
            log.notice("🔍   [\(index, privacy: .public)] timeRange=[\(instruction.timeRange.start.seconds, privacy: .public)..<\(instruction.timeRange.end.seconds, privacy: .public)] layers=\(instruction.layerInstructions.count, privacy: .public)")
        }
        log.notice("🔍 audioMix present=\(project.audioMix != nil, privacy: .public) musicSkippedAsProtected=\(project.musicSkippedAsProtected, privacy: .public)")
    }

    private func stage<T>(_ label: String, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as ExportStageError {
            throw error
        } catch {
            throw ExportStageError(stage: label, underlying: error)
        }
    }

    private func performExport() async {
        AnalyticsLogger.log(.exportStarted)
        isExporting = true
        exportProgress = 0
        wasBackgroundedDuringExport = false
        defer { isExporting = false }

        // Bez tego: ekran gaśnie po chwili bezczynności, telefon się
        // automatycznie blokuje, a iOS usypia appkę w trakcie renderowania
        // — user: "budowa klipu się przerywa". Blokada uśpienia ekranu
        // WYŁĄCZNIE na czas eksportu (przywracana zawsze, też przy błędzie).
        // Dodatkowo `beginBackgroundTask` — gdyby user mimo to ręcznie
        // zablokował telefon przyciskiem bocznym albo przełączył appkę,
        // daje kilkanaście-kilkadziesiąt sekund więcej na dokończenie
        // zamiast natychmiastowego zawieszenia (nie jest to gwarancja przy
        // BARDZO długim zablokowaniu, ale realnie chroni krótkie odejścia).
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PMemories Export") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        defer { UIApplication.shared.endBackgroundTask(backgroundTaskID) }

        // Karta brandingowa PMemories (niżej) renderuje się do plików
        // tymczasowych — `AVMutableComposition` czyta je leniwie, więc muszą
        // przetrwać do końca `buildComposition`/`exportAndSaveToPhotos`
        // poniżej, ale POTEM są zbędne. `defer` na poziomie całej funkcji,
        // żeby posprzątać niezależnie od tego czy eksport się powiódł
        // (04.08.2026, user: "apka ma być lekka i nie ma zaśmiecać telefonu"
        // — patrz `TempFileCleanup`).
        var brandingOutroURLs: [URL] = []
        defer { for url in brandingOutroURLs { try? FileManager.default.removeItem(at: url) } }

        // Powiadomienie po zakończeniu — user 31.07.2026: "żeby można było
        // robić coś innego i tylko dostać komunikat". Nie gwarantuje że
        // BARDZO długi eksport dokończy się przy w pełni zablokowanym
        // telefonie (patrz `ExportNotifier`), ale mówi prawdę o wyniku.
        ExportNotifier.requestAuthorizationIfNeeded()

        do {
            var exportItems = items

            // Karta brandingowa PMemories — doklejana do KAŻDEGO eksportu,
            // bez wyjątku (12/13.08.2026, user na etapie TestFlight: "niech
            // każdy wygenerowany Memory będzie małą reklamą aplikacji",
            // świadomie bez opcji wyłączenia na razie). Tekst każdej fazy
            // wypalony w pikselach (16.08.2026, patrz komentarz w
            // `PMemoriesOutroCardRenderer` — poprzednia nakładka `CATextLayer`
            // potrafiła zawieść po cichu), fazy sklejone `.crossfade` — tło
            // identyczne w obu fazach, więc wygląda jak jedna ciągła scena,
            // nie sklejone slajdy. `mutesBackgroundMusic: true` — user: "to
            // będzie wstawka już bez muzyki na końcu".
            let outroClipURLs = await PMemoriesOutroCardRenderer.renderOutroClips(size: exportQuality.canvasSize)
            brandingOutroURLs.append(contentsOf: outroClipURLs)
            for clipURL in outroClipURLs {
                exportItems.append(MediaItem(
                    pickerItemId: nil, isLivePhoto: false, isVideo: true, thumbnail: nil,
                    useMotion: false, videoURL: clipURL, duration: PMemoriesOutroCardRenderer.phaseDuration,
                    transitionStyle: .crossfade, mutesBackgroundMusic: true
                ))
            }

            // Wagi dobrane z dzisiejszej diagnozy — renderowanie zdjęć
            // (`buildComposition`) to dominujący koszt czasowy przy
            // projektach z wieloma zdjęciami. Bez żadnego dodatkowego
            // przebiegu: 0...0.6 / 0.6...1.0 (jak dotąd). Z filtrem
            // kolorystycznym (`ColorGrader`) i/lub premium przejściami
            // (`PremiumTransitionGrader`, 30.08.2026) — po jednym dodatkowym
            // odcinku na KAŻDY użyty przebieg, reszta ściśnięta żeby
            // zmieścić. `mayUsePremiumTransitions` liczone TU, przed
            // `buildComposition` (nie po) — appka wie z wyprzedzeniem czy
            // premium styl może się pojawić: ręcznym override per-klip w
            // Trim, albo (dla Foundera, patrz `TesterRegistry.
            // hasPremiumUnlocked`) przez pulę auto-doboru `enabledTransitions`.
            let hasColorStyle = colorStyle != .none
            let mayUsePremiumTransitions = items.contains { $0.transitionStyle?.premiumEffect != nil }
                || enabledTransitions.contains { $0.premiumEffect != nil }
            let extraPasses = (hasColorStyle ? 1 : 0) + (mayUsePremiumTransitions ? 1 : 0)
            let buildWeight = extraPasses > 0 ? 0.45 : 0.6
            let exportWeight = extraPasses > 0 ? 0.3 : 0.4
            let perPassWeight = extraPasses > 0 ? 0.25 / Double(extraPasses) : 0.0
            let gradeWeight = hasColorStyle ? perPassWeight : 0.0
            let premiumWeight = mayUsePremiumTransitions ? perPassWeight : 0.0

            let composedProject = try await stage("composition") {
                try await VideoComposer.buildComposition(
                    items: exportItems,
                    audioURL: selectedSong?.assetURL,
                    musicVolume: musicVolume,
                    captions: captions,
                    overlays: overlays,
                    quality: exportQuality,
                    enabledTransitionStyles: Array(enabledTransitions),
                    onProgress: { progress in exportProgress = progress * buildWeight }
                )
            }
            // 24.08.2026 — realny bug (`-11838`/`FigAssetExportSession
            // -16976`, pada NATYCHMIAST w `createRemakerAndBeginExport`,
            // przed czytaniem jakichkolwiek próbek) przetrwał już 6
            // nieskutecznych, punktowych poprawek (kolor/kodek/współbieżność/
            // preset/IOSurface/cicha ścieżka audio) — zamiast zgadywać
            // siódmą zmienną naraz, pełny zrzut STRUKTURY kompozycji tuż
            // przed `mainExport`, żeby przy kolejnym realnym powtórzeniu
            // (patrz `print` niżej, trafia do device syslog) mieć KOMPLETNY
            // obraz do porównania z udanymi eksportami, zamiast jednej
            // zmiennej na raz.
            logCompositionDiagnostics(composedProject, items: exportItems)

            // Plik(i) tymczasowe — sprzątane niezależnie od tego, czy filtr
            // był użyty, i niezależnie od tego czy eksport się powiódł
            // (04.08.2026, "apka ma być lekka i nie ma zaśmiecać telefonu").
            var renderedURL: URL?
            var premiumGradedURL: URL?
            var gradedURL: URL?
            defer {
                if let renderedURL { try? FileManager.default.removeItem(at: renderedURL) }
                if let premiumGradedURL { try? FileManager.default.removeItem(at: premiumGradedURL) }
                if let gradedURL { try? FileManager.default.removeItem(at: gradedURL) }
            }
            let exportedURL = try await stage("mainExport") {
                try await VideoExporter.export(composedProject: composedProject, onProgress: { progress in
                    exportProgress = buildWeight + progress * exportWeight
                })
            }
            renderedURL = exportedURL

            var finalURL = exportedURL
            if !composedProject.premiumTransitionWindows.isEmpty {
                let filtered = try await stage("premiumTransitionGrade") {
                    try await PremiumTransitionGrader.apply(
                        composedProject.premiumTransitionWindows, canvasSize: exportQuality.canvasSize, to: finalURL,
                        onProgress: { progress in exportProgress = buildWeight + exportWeight + progress * premiumWeight }
                    )
                }
                premiumGradedURL = filtered
                finalURL = filtered
            }
            if hasColorStyle {
                let filtered = try await stage("colorGrade") {
                    try await ColorGrader.apply(colorStyle, to: finalURL, onProgress: { progress in
                        exportProgress = buildWeight + exportWeight + premiumWeight + progress * gradeWeight
                    })
                }
                gradedURL = filtered
                finalURL = filtered
            }

            let assetIdentifier = try await stage("saveToPhotos") {
                try await VideoExporter.saveToPhotos(fileURL: finalURL)
            }
            project.exportedAssetIdentifier = assetIdentifier
            syncProject()
            try? modelContext.save()
            didExportSucceed = true
            // 15.09.2026 — patrz `AnalyticsLogger`. `mayUsePremiumTransitions`
            // już policzone wyżej (przed `buildComposition`) — reużywane tu
            // zamiast liczyć drugi raz.
            AnalyticsLogger.log(.exportCompleted(
                durationSeconds: composedProject.composition.duration.seconds,
                usedColorFilter: hasColorStyle,
                usedPremiumBoundTransition: mayUsePremiumTransitions
            ))
            ExportNotifier.notify(
                title: L("Your movie is ready!"),
                body: project.title.isEmpty ? L("Saved to your camera roll.") : project.title
            )
            checkTripMemoryMatch()
            resolveMemoryLocationIfNeeded()
        } catch {
            // Zamiast kryptycznego kodu AVFoundation ("Operation Stopped")
            // gdy iOS przerwał eksport bo appka zeszła z pierwszego planu —
            // patrz komentarz przy `wasBackgroundedDuringExport`.
            let message: String
            if wasBackgroundedDuringExport {
                message = L("Export was interrupted because PMemories left the foreground. Keep the app open while exporting to avoid this.")
            } else {
                // 23.08.2026 — drugi realny bug report testera z tym samym
                // nieinformatywnym "Operation Stopped"/"ComposerError error 1",
                // a tester nie ma dostępu do konsoli Xcode żeby przekazać coś
                // więcej niż zrzut ekranu z samym alertem. Dotąd prawdziwy kod
                // błędu AVFoundation ginął bezpowrotnie po zamknięciu alertu —
                // ten sam problem co przy Travel Map (patrz
                // `TravelMapVideoRenderer.lastProfileSummary`), to samo
                // rozwiązanie: dopisujemy surowy domain/code wprost do
                // komunikatu, więc sam zrzut ekranu wystarczy do diagnozy.
                if let stageError = error as? ExportStageError {
                    message = "\(stageError.underlying.localizedDescription) [\(stageError.stage): \(describeErrorChain(stageError.underlying))]"
                } else {
                    message = "\(error.localizedDescription) [\(describeErrorChain(error))]"
                }
            }
            exportError = message
            ExportNotifier.notify(title: L("Export failed"), body: message)
        }
    }

    /// "Share with Family" tłumaczenia napisów — SwiftData nie wspiera
    /// wprost `[String: String]`, więc `SavedCaption.translationsJSON`
    /// trzyma je jako zserializowany JSON.
    private func decodeTranslations(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func encodeTranslations(_ translations: [String: String]) -> String? {
        guard !translations.isEmpty, let data = try? JSONEncoder().encode(translations) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Odtwarza wcześniej wybrany utwór (jeśli projekt był już zapisany z
    /// muzyką) po `persistentID` — jedyny stabilny sposób odnalezienia tego
    /// samego utworu ponownie przez `MPMediaQuery`.
    private func loadInitialSong() {
        musicVolume = project.musicVolume
        if let raw = project.enabledTransitionStylesRaw {
            let premiumUnlocked = TesterRegistry.hasPremiumUnlocked(AuthManager.shared.userIdentifier)
            let parsed = Set(raw.split(separator: ",").compactMap { TransitionStyle(rawValue: String($0)) }.filter { !$0.isPremium || premiumUnlocked })
            enabledTransitions = parsed.isEmpty ? Set(TransitionStyle.allCases.filter { !$0.isPremium || premiumUnlocked }) : parsed
        }
        colorStyle = project.colorStyleRaw.flatMap(ColorStyle.init(rawValue:)) ?? .none
        captions = project.captions.sorted(by: { $0.order < $1.order }).map { saved in
            Caption(
                text: saved.text, startTime: saved.startTime, endTime: saved.endTime,
                position: CaptionPosition(rawValue: saved.positionRawValue) ?? .bottom,
                font: CaptionFont(rawValue: saved.fontRawValue) ?? .helvetica,
                translations: decodeTranslations(saved.translationsJSON)
            )
        }
        guard let persistentID = project.musicPersistentID else { return }
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: persistentID, forProperty: MPMediaItemPropertyPersistentID
        ))
        selectedSong = query.items?.first
    }

    /// Wołane PO udanym eksporcie (30.08.2026) — sprawdza czy ten projekt
    /// pasuje lokalizacją zdjęć do jakiegoś nieprzypisanego przystanku w
    /// zaplanowanej podróży (`TripMemoryMatcher`), i jeśli tak, pyta usera
    /// czy połączyć. Pomija projekty JUŻ powiązane z jakimkolwiek przystankiem
    /// (żeby nie proponować drugiego linku dla tego samego filmu przy
    /// ponownym eksporcie) i nie proponuje NIC gdy user właśnie odrzucił tę
    /// samą propozycję w tej sesji edycji (`tripMemorySuggestion` zostaje
    /// `nil` po "Not Now", `checkTripMemoryMatch` się nie odpala ponownie
    /// samo z siebie — tylko po kolejnym eksporcie).
    private func checkTripMemoryMatch() {
        let alreadyLinked = savedTrips.contains { $0.stops.contains { $0.linkedProjectID == project.id } }
        guard !alreadyLinked else { return }
        tripMemorySuggestion = TripMemoryMatcher.bestMatch(for: project, trips: savedTrips)
    }

    /// Kraj/miasto z GPS zdjęć TEGO projektu (30.08.2026) — patrz komentarz
    /// przy `SavedProject.detectedCountryCode`. Rozwiązywane RAZ (guard na
    /// `nil`, nie nadpisuje przy kolejnych eksportach tego samego projektu)
    /// i NIEZALEŻNIE od tego, czy `checkTripMemoryMatch` znalazło/user
    /// potwierdził link do przystanku — link do przystanku dzieje się
    /// asynchronicznie (dopiero po potwierdzeniu alertu przez usera), więc
    /// appka nie może czekać na tę decyzję zanim zapisze wykrytą lokalizację.
    /// `TravelAchievementsCalculator.explorerScore` sam pomija projekty JUŻ
    /// powiązane z przystankiem, żeby uniknąć podwójnego liczenia.
    private func resolveMemoryLocationIfNeeded() {
        guard project.detectedCountryCode == nil, project.detectedCityName == nil else { return }
        let identifiers = project.items.map(\.assetLocalIdentifier).filter { !$0.isEmpty }
        guard !identifiers.isEmpty, let location = MediaAssetLoader.firstLocation(forAssetLocalIdentifiers: identifiers) else { return }
        Task {
            guard let resolved = await CityGeocoder.reverseResolveFull(location) else { return }
            project.detectedCountryCode = resolved.countryCode
            project.detectedCityName = resolved.city
            try? modelContext.save()
        }
    }

    /// Zapisuje bieżący stan (kolejność, ruch Live Photo, czas trwania,
    /// muzyka) do `project` — wywoływane po każdej znaczącej zmianie zamiast
    /// przy każdym drobnym mutowaniu, żeby nie robić tego na każdą klatkę.
    private func syncProject() {
        project.updatedAt = Date()
        project.musicPersistentID = selectedSong?.persistentID
        project.musicVolume = musicVolume
        project.enabledTransitionStylesRaw = enabledTransitions.map(\.rawValue).joined(separator: ",")
        project.colorStyleRaw = colorStyle == .none ? nil : colorStyle.rawValue
        for existing in project.items { modelContext.delete(existing) }
        project.items = items.enumerated().compactMap { index, item in
            guard let identifier = item.pickerItemId else { return nil }
            return SavedMediaItem(
                assetLocalIdentifier: identifier, isLivePhoto: item.isLivePhoto, isVideo: item.isVideo,
                useMotion: item.useMotion, duration: item.duration, order: index,
                trimStart: item.trimStart, isManuallyTrimmed: item.isManuallyTrimmed, speed: item.speed,
                rotationDegrees: item.rotationDegrees, cropFill: item.cropFill, originalVolume: item.originalVolume,
                transitionStyleRawValue: item.transitionStyle?.rawValue
            )
        }
        for existing in project.captions { modelContext.delete(existing) }
        project.captions = captions.enumerated().map { index, caption in
            SavedCaption(
                text: caption.text, startTime: caption.startTime, endTime: caption.endTime,
                positionRawValue: caption.position.rawValue, fontRawValue: caption.font.rawValue,
                translationsJSON: encodeTranslations(caption.translations), order: index
            )
        }
        for existing in project.overlays { modelContext.delete(existing) }
        project.overlays = overlays.enumerated().compactMap { index, overlay in
            guard let identifier = overlay.pickerItemId else { return nil }
            return SavedOverlayItem(
                assetLocalIdentifier: identifier, isLivePhoto: overlay.isLivePhoto, isVideo: overlay.isVideo,
                useMotion: overlay.useMotion, globalStartTime: overlay.globalStartTime, duration: overlay.duration,
                cornerRawValue: overlay.corner.rawValue, sizeScale: overlay.sizeScale, order: index
            )
        }
    }
}

private struct TimelineThumbnail: View {
    @Binding var item: MediaItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Palette.blue : .clear, lineWidth: 2)
            )

            if item.isLivePhoto {
                Toggle("", isOn: $item.useMotion)
                    .labelsHidden()
                    .scaleEffect(0.55)
                    .offset(x: 8, y: 8)
            } else if item.isVideo {
                // Mały play w rogu — user 31.07.2026: "podglądzie wszystkich
                // zdjęć/wideo w edytorze żeby wiedzieć który to który"; do
                // teraz zdjęcia i wideo wyglądały identycznie w timeline.
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }
        }
    }
}

/// Miniaturka w `overlayRow` — mniejsza od `TimelineThumbnail` (48pt, nie
/// 60pt) i bez toggle'a ruchu Live Photo (Faza 1 nakładek zawsze odtwarza
/// pełne źródło od początku, bez ruchu/przycinania — patrz `Docs/Studio.md`).
/// Mała ikonka w rogu przypomina że to nakładka PiP, nie zwykły klip.
private struct OverlayThumbnail: View {
    let overlay: OverlayItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail = overlay.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.blue.opacity(0.6), lineWidth: 1.5)
            )

            Image(systemName: "pip")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(Palette.blue, in: Circle())
                .offset(x: 4, y: 4)
        }
    }
}

private struct ToolbarButton: View {
    let icon: String
    let title: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? Palette.blue : Color.primary)
            .frame(maxWidth: .infinity)
        }
    }
}
