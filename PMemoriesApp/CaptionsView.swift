import SwiftUI
import Translation

/// Zarządzanie napisami — lista + dodawanie/edycja/usuwanie. `totalDuration`
/// to długość CAŁEGO finalnego filmiku (suma `MediaItem.duration`), do
/// ograniczenia suwaków czasu startu/końca napisu.
struct CaptionsView: View {
    @Binding var captions: [Caption]
    let totalDuration: Double
    @Environment(\.dismiss) private var dismiss

    // "Share with Family" (TODO.md, dopisane 30.07.2026) — tłumaczenie
    // wszystkich napisów naraz na wybrane języki, wypalane RAZEM z
    // oryginałem w eksportowanym filmie (patrz `VideoComposer.
    // captionsAnimationTool`). Tłumaczenie idzie sekwencyjnie, jeden język
    // na raz — `TranslationSession` (framework `Translation`, on-device,
    // ten sam silnik co PMTalk) obsługuje jedną parę źródło→cel na sesję.
    @State private var isShowingLanguagePicker = false
    @State private var selectedShareLanguages: Set<String> = []
    @State private var translationQueue: [String] = []
    @State private var currentTranslatingCode: String?
    @State private var activeTranslationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false

    var body: some View {
        NavigationStack {
            List {
                if !captions.isEmpty {
                    Section {
                        Button {
                            isShowingLanguagePicker = true
                        } label: {
                            HStack {
                                Label(L("Share with Family"), systemImage: "globe")
                                Spacer()
                                if isTranslating {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isTranslating)
                    } footer: {
                        Text(L("Add translations of your captions — shown together with the original, right in the exported video."))
                    }
                }

                ForEach(captions.indices, id: \.self) { index in
                    CaptionRow(caption: $captions[index], totalDuration: totalDuration) {
                        captions.remove(at: index)
                    }
                }
                .onDelete { indices in
                    captions.remove(atOffsets: indices)
                }

                Button {
                    addCaption()
                } label: {
                    Label("Add Caption", systemImage: "plus.circle")
                }
            }
            .navigationTitle("Captions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingLanguagePicker) {
                ShareLanguagePicker(selected: $selectedShareLanguages) {
                    startTranslation()
                }
            }
            .translationTask(activeTranslationConfig) { session in
                await translateAll(using: session)
            }
        }
    }

    private func startTranslation() {
        translationQueue = Array(selectedShareLanguages)
        advanceTranslationQueue()
    }

    private func advanceTranslationQueue() {
        guard !translationQueue.isEmpty else {
            isTranslating = false
            activeTranslationConfig = nil
            currentTranslatingCode = nil
            return
        }
        isTranslating = true
        let code = translationQueue.removeFirst()
        currentTranslatingCode = code
        activeTranslationConfig = TranslationSession.Configuration(target: Locale.Language(identifier: code))
    }

    /// Tłumaczy WSZYSTKIE napisy na jeden, aktualny język z kolejki, potem
    /// przechodzi do następnego (`advanceTranslationQueue`). Języki
    /// niewspierane na tym urządzeniu (brak pobranego modelu / brak
    /// wsparcia) po prostu nie dostają tłumaczenia dla żadnego napisu —
    /// reszta kolejki jedzie dalej, bez przerywania całości.
    private func translateAll(using session: TranslationSession) async {
        guard let code = currentTranslatingCode else { return }
        for index in captions.indices {
            let text = captions[index].text
            guard !text.isEmpty else { continue }
            do {
                let response = try await session.translate(text)
                captions[index].translations[code] = response.targetText
            } catch {
                break
            }
        }
        advanceTranslationQueue()
    }

    /// Nowy napis startuje tam, gdzie kończy się ostatni (albo od 0, jeśli
    /// to pierwszy) — żeby nie nakładać się domyślnie na poprzedni.
    private func addCaption() {
        let start = captions.map(\.endTime).max() ?? 0
        let clampedStart = min(start, max(0, totalDuration - 3))
        captions.append(Caption(text: L("New caption"), startTime: clampedStart, endTime: min(clampedStart + 3, totalDuration)))
    }
}

private struct CaptionRow: View {
    @Binding var caption: Caption
    let totalDuration: Double
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Pole tekstowe pokazuje się w WYBRANEJ czcionce — user
                // 31.07.2026: "nie zauważyłem różnicy" — do teraz appka nie
                // miała ŻADNEGO podglądu czcionki podczas edycji, wybór
                // trafiał tylko do finalnego eksportu (`VideoComposer.
                // captionsAnimationTool`), nigdy do UI edycji.
                TextField("Caption text", text: $caption.text)
                    .font(.custom(caption.font.rawValue, size: 20))
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            if !caption.translations.isEmpty {
                Text(caption.translations.keys.sorted().map { $0.uppercased() }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(format(caption.startTime))s – \(format(caption.endTime))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Position", selection: $caption.position) {
                    ForEach(CaptionPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .pickerStyle(.menu)

                // Każda opcja pokazuje "Aa" wyrenderowane W TEJ czcionce —
                // realny wybór wizualny, nie tylko nazwa stylu.
                Picker("Font", selection: $caption.font) {
                    ForEach(CaptionFont.allCases) { font in
                        Label {
                            Text(font.label)
                        } icon: {
                            Text("Aa").font(.custom(font.rawValue, size: 16))
                        }
                        .tag(font)
                    }
                }
                .pickerStyle(.menu)
            }

            if totalDuration > 0 {
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { caption.startTime },
                        set: { caption.startTime = min($0, caption.endTime - 0.2) }
                    ),
                    in: 0...max(0.1, totalDuration)
                )
                Text("End")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { caption.endTime },
                        set: { caption.endTime = max($0, caption.startTime + 0.2) }
                    ),
                    in: 0...max(0.1, totalDuration)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%.1f", seconds)
    }
}

/// Wybór docelowych języków dla "Share with Family" — reużywa listę
/// `AppLanguage` (bez "System", to nie jest wybór języka appki).
private struct ShareLanguagePicker: View {
    @Binding var selected: Set<String>
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(AppLanguage.allCases.filter { $0 != .system }) { language in
                Button {
                    if selected.contains(language.rawValue) {
                        selected.remove(language.rawValue)
                    } else {
                        selected.insert(language.rawValue)
                    }
                } label: {
                    HStack {
                        Text(language.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(language.rawValue) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.blue)
                        }
                    }
                }
            }
            .navigationTitle(L("Choose Languages"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Translate")) {
                        dismiss()
                        onConfirm()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
