import SwiftUI
import PhotosUI
import MediaPlayer
import SwiftData
import UIKit
import AVFoundation

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
    @State private var enabledTransitions: Set<TransitionStyle> = Set(TransitionStyle.allCases)
    @State private var isShowingStyle = false
    /// Filtr kolorystyczny (09.08.2026) — patrz `StyleView`/`ColorGrader`.
    @State private var colorStyle: ColorStyle = .none
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

    var body: some View {
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
        .alert("Saved to camera roll", isPresented: $didExportSucceed) {
            Button("OK", role: .cancel) {}
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
                isShowingMusicPicker = true
            }
            ToolbarButton(icon: "paintpalette", title: L("Style"), isActive: colorStyle != .none) {
                isShowingStyle = true
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

    private func performExport() async {
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
            // projektach z wieloma zdjęciami. Bez filtra: 0...0.6 / 0.6...1.0
            // (jak dotąd). Z filtrem (`ColorGrader`, drugi pełny przebieg):
            // dodatkowy odcinek na końcu, reszta ściśnięta żeby zmieścić.
            let hasColorStyle = colorStyle != .none
            let buildWeight = hasColorStyle ? 0.45 : 0.6
            let exportWeight = hasColorStyle ? 0.3 : 0.4
            let gradeWeight = hasColorStyle ? 0.25 : 0.0

            let composedProject = try await VideoComposer.buildComposition(
                items: exportItems,
                audioURL: selectedSong?.assetURL,
                musicVolume: musicVolume,
                captions: captions,
                overlays: overlays,
                quality: exportQuality,
                enabledTransitionStyles: Array(enabledTransitions),
                onProgress: { progress in exportProgress = progress * buildWeight }
            )
            // Plik(i) tymczasowe — sprzątane niezależnie od tego, czy filtr
            // był użyty, i niezależnie od tego czy eksport się powiódł
            // (04.08.2026, "apka ma być lekka i nie ma zaśmiecać telefonu").
            var renderedURL: URL?
            var gradedURL: URL?
            defer {
                if let renderedURL { try? FileManager.default.removeItem(at: renderedURL) }
                if let gradedURL { try? FileManager.default.removeItem(at: gradedURL) }
            }
            let exportedURL = try await VideoExporter.export(composedProject: composedProject, onProgress: { progress in
                exportProgress = buildWeight + progress * exportWeight
            })
            renderedURL = exportedURL

            var finalURL = exportedURL
            if hasColorStyle {
                let filtered = try await ColorGrader.apply(colorStyle, to: exportedURL, onProgress: { progress in
                    exportProgress = buildWeight + exportWeight + progress * gradeWeight
                })
                gradedURL = filtered
                finalURL = filtered
            }

            let assetIdentifier = try await VideoExporter.saveToPhotos(fileURL: finalURL)
            project.exportedAssetIdentifier = assetIdentifier
            syncProject()
            try? modelContext.save()
            didExportSucceed = true
            ExportNotifier.notify(
                title: L("Your movie is ready!"),
                body: project.title.isEmpty ? L("Saved to your camera roll.") : project.title
            )
        } catch {
            // Zamiast kryptycznego kodu AVFoundation ("Operation Stopped")
            // gdy iOS przerwał eksport bo appka zeszła z pierwszego planu —
            // patrz komentarz przy `wasBackgroundedDuringExport`.
            let message = wasBackgroundedDuringExport
                ? L("Export was interrupted because PMemories left the foreground. Keep the app open while exporting to avoid this.")
                : error.localizedDescription
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
            let parsed = Set(raw.split(separator: ",").compactMap { TransitionStyle(rawValue: String($0)) })
            enabledTransitions = parsed.isEmpty ? Set(TransitionStyle.allCases) : parsed
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
