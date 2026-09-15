import SwiftUI
import MediaPlayer

/// "AI Director" (30.08.2026) — user: "zacznijmy budowe AI dodam ze w apce
/// bedziemy miec mozliwosc z AI albo bez do wyboru przez uzytkownika".
/// Pierwsza funkcja modułu AI z `Docs/AI.md`: jedno zdanie opisujące nastrój
/// → appka dobiera filtr kolorystyczny, pulę przejść i tempo cięć w JUŻ
/// istniejącym silniku Studio (`ColorStyle`/`TransitionStyle`/`MediaItem.
/// speed`) — zero nowego pipeline'u renderowania. Rozumienie zdania usera
/// całkowicie ON-DEVICE (`AIDirectorEngine`/`FoundationModels`), nic nie
/// wychodzi poza telefon. Presety działają ZAWSZE i realizują wymóg "z AI
/// albo bez" — przy AI wyłączonym w Profilu (albo na telefonie bez Apple
/// Intelligence) appka pokazuje TYLKO presety, bez pola tekstowego.
///
/// Podpowiedzi piosenek (31.08.2026, user: "czy AI moze podpowiadac
/// piosenke") — po zastosowaniu stylu appka przeszukuje WŁASNĄ bibliotekę
/// usera (`MusicLibrarySuggester`) po gatunku pasującym do wybranego
/// nastroju, patrz `songsSection`.
struct AIDirectorView: View {
    @Binding var items: [MediaItem]
    @Binding var colorStyle: ColorStyle
    @Binding var enabledTransitions: Set<TransitionStyle>
    @Binding var selectedSong: MPMediaItem?
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var descriptionText = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var appliedHint: String?
    @State private var suggestedSongs: [MPMediaItem] = []
    @State private var isLoadingSongs = false
    @State private var hasSearchedSongs = false

    private var availability: AIDirectorAvailability { AIDirectorEngine.availability }

    var body: some View {
        NavigationStack {
            List {
                if availability.isUsable {
                    aiSection
                } else {
                    Section {
                        Text(unavailableMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                presetsSection

                if let appliedHint {
                    Section {
                        Label(appliedHint, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasSearchedSongs {
                    songsSection
                }
            }
            .navigationTitle(L("AI Director"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private var aiSection: some View {
        Section {
            TextField(L("e.g. emotional and slow, or fast TikTok style"), text: $descriptionText, axis: .vertical)
                .lineLimit(2...4)
            Button {
                Task { await runAI() }
            } label: {
                HStack {
                    if isThinking { ProgressView().padding(.trailing, 4) }
                    Text(L("Suggest Style"))
                }
            }
            .disabled(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text(L("Describe the mood"))
        } footer: {
            Text(L("Runs entirely on your device — nothing is sent anywhere."))
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(AIDirectorEngine.presets) { preset in
                Button {
                    apply(preset.style, hint: preset.style.musicHint)
                } label: {
                    HStack {
                        Image(systemName: preset.icon)
                            .foregroundStyle(Palette.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).foregroundStyle(.primary)
                            Text(preset.style.musicHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(L("Presets"))
        }
    }

    /// Utwory Z BIBLIOTEKI usera pasujące do gatunku wybranego stylu —
    /// wyniki niepuste tylko gdy user faktycznie ma coś pasującego (appka
    /// nie zmyśla/nie sugeruje utworów, których nie ma). Tapnięcie od razu
    /// USTAWIA utwór jako muzykę projektu — bez otwierania osobnego pickera.
    private var songsSection: some View {
        Section {
            if isLoadingSongs {
                HStack {
                    ProgressView()
                    Text(L("Searching your library…"))
                        .foregroundStyle(.secondary)
                }
            } else if suggestedSongs.isEmpty {
                Text(L("No matching songs found in your library."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestedSongs, id: \.persistentID) { song in
                    Button {
                        selectedSong = song
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title ?? L("Unknown"))
                                    .foregroundStyle(.primary)
                                if let artist = song.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedSong?.persistentID == song.persistentID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.blue)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(L("Songs From Your Library"))
        } footer: {
            Text(L("Matched by genre to the style above — only songs you actually have."))
        }
    }

    private var unavailableMessage: String {
        switch availability {
        case .disabledByUser:
            return L("AI features are turned off in your Profile settings. Turn them on to describe your own style in a sentence — or just pick a preset below.")
        case .appleIntelligenceNotEnabled:
            return L("Turn on Apple Intelligence in Settings to describe your own style in a sentence — or just pick a preset below.")
        case .modelNotReady:
            return L("The on-device AI model is still downloading. Try again in a bit — or just pick a preset below.")
        case .deviceNotEligible, .available:
            return L("Your device doesn't support on-device AI. Pick a preset below instead.")
        }
    }

    private func runAI() async {
        // 15.09.2026 — patrz `AnalyticsLogger`. Pełny przebieg AI (opis
        // zdaniem → dobór stylu) to funkcja idąca do Premium (`Pricing.md`
        // 15.09.2026: presety zawsze darmowe, pełne AI Premium) — appka
        // dziś jej nie blokuje, loguje ZAMIAR.
        AnalyticsLogger.log(.premiumFeatureTapped(feature: "ai_director_full", source: "studio"))
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }
        do {
            let style = try await AIDirectorEngine.suggestStyle(from: descriptionText)
            apply(style, hint: style.reasoning ?? style.musicHint)
        } catch {
            errorMessage = L("Couldn't come up with a style — try a preset instead.")
        }
    }

    private func apply(_ style: AIDirectorStyle, hint: String) {
        colorStyle = style.colorStyle
        enabledTransitions = style.transitionPool
        for index in items.indices {
            let newSpeed = items[index].speed * style.paceMultiplier
            items[index].speed = min(max(newSpeed, 0.25), 4.0)
        }
        appliedHint = hint
        onApply()
        Task { await loadSongSuggestions(for: style) }
    }

    private func loadSongSuggestions(for style: AIDirectorStyle) async {
        isLoadingSongs = true
        suggestedSongs = await MusicLibrarySuggester.suggestions(matchingAny: style.musicGenreKeywords)
        isLoadingSongs = false
        hasSearchedSongs = true
    }
}
