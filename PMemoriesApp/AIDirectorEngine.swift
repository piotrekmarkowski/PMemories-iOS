import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Dlaczego AI Director akurat teraz NIE może liczyć na model — pokazywane
/// userowi zamiast po prostu chować pole tekstowe bez wyjaśnienia (30.08.2026,
/// user chciał osobny toggle "z AI albo bez", więc appka musi umieć
/// powiedzieć, KTÓRY z dwóch powodów — świadomy wybór usera czy ograniczenie
/// urządzenia — akurat obowiązuje).
enum AIDirectorAvailability: Equatable {
    case available
    case disabledByUser
    case appleIntelligenceNotEnabled
    case modelNotReady
    case deviceNotEligible

    var isUsable: Bool { self == .available }
}

/// Silnik "AI Director" — CAŁKOWICIE on-device (`FoundationModels`, iOS 26+,
/// user: świadomie wybrane zamiast chmury, "z AI albo bez do wyboru przez
/// użytkownika"). Presety (`presets`) działają ZAWSZE, niezależnie od AI —
/// to one realizują wymóg działania appki "bez AI": przy wyłączonym toggle w
/// Profilu albo na telefonie bez Apple Intelligence, `AIDirectorView` po
/// prostu nie pokazuje pola tekstowego i user wybiera z gotowej listy.
enum AIDirectorEngine {
    static let aiEnabledKey = "aiFeaturesEnabled"

    enum EngineError: Error {
        case unavailable
    }

    static var availability: AIDirectorAvailability {
        let enabledByUser = UserDefaults.standard.object(forKey: aiEnabledKey) as? Bool ?? true
        guard enabledByUser else { return .disabledByUser }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable:
                return .deviceNotEligible
            }
        }
        #endif
        return .deviceNotEligible
    }

    /// Pyta model o styl na podstawie zdania usera — wołane TYLKO gdy
    /// `availability == .available` (patrz `AIDirectorView`), stąd
    /// `EngineError.unavailable` niżej to w praktyce nieosiągalna gałąź
    /// bezpieczeństwa, nie oczekiwana ścieżka.
    static func suggestStyle(from description: String) async throws -> AIDirectorStyle {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
            You are a movie-editing assistant inside a travel-memories app called PMemories. \
            Given a short description of the mood or style the user wants for their movie, pick \
            exactly one cutting pace and one color look that best matches it, and write one short, \
            friendly sentence (max 20 words) in the SAME language the user wrote in, explaining the \
            choice and suggesting a music genre or mood to search for.
            """)
            let response = try await session.respond(to: description, generating: Suggestion.self)
            return response.content.asDirectorStyle
        }
        #endif
        throw EngineError.unavailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct Suggestion {
        @Guide(description: "Overall cutting pace: slow and lingering, balanced, or fast and energetic")
        var pace: Pace
        @Guide(description: "Color grading look that best matches the requested mood")
        var look: Look
        @Guide(description: "One short sentence (max 20 words), in the same language as the user's description, explaining the choice and suggesting a music genre or mood")
        var note: String

        @Generable
        enum Pace {
            case slow
            case medium
            case fast
        }

        @Generable
        enum Look {
            case none
            case vintage
            case blackAndWhite
            case vibrant
            case cinematic
            case warm
        }
    }
    #endif

    static let presets: [AIDirectorPreset] = [
        AIDirectorPreset(
            name: L("Cinematic"), icon: "film",
            style: AIDirectorStyle(
                colorStyle: .cinematic,
                transitionPool: [.crossfade, .zoomOut, .slide],
                paceMultiplier: 1.0,
                musicHint: L("Try orchestral or ambient music"),
                musicGenreKeywords: ["Soundtrack", "Classical", "Ambient", "Cinematic"],
                reasoning: nil
            )
        ),
        AIDirectorPreset(
            name: L("Emotional"), icon: "heart",
            style: AIDirectorStyle(
                colorStyle: .warm,
                transitionPool: [.crossfade, .zoomOut],
                paceMultiplier: 0.85,
                musicHint: L("Try a soft piano or acoustic ballad"),
                musicGenreKeywords: ["Piano", "Acoustic", "Ballad", "Classical"],
                reasoning: nil
            )
        ),
        AIDirectorPreset(
            name: L("Energetic"), icon: "bolt",
            style: AIDirectorStyle(
                colorStyle: .vibrant,
                transitionPool: [.zoom, .slideLeft, .slideUp, .slideDown, .diagonal, .squeeze],
                paceMultiplier: 1.35,
                musicHint: L("Try upbeat pop or electronic music"),
                musicGenreKeywords: ["Pop", "Electronic", "Dance", "EDM"],
                reasoning: nil
            )
        ),
        AIDirectorPreset(
            name: L("Calm Travel"), icon: "leaf",
            style: AIDirectorStyle(
                colorStyle: .none,
                transitionPool: [.crossfade],
                paceMultiplier: 0.9,
                musicHint: L("Try lo-fi or acoustic guitar"),
                musicGenreKeywords: ["Lo-Fi", "Acoustic", "Chill", "Ambient"],
                reasoning: nil
            )
        ),
        AIDirectorPreset(
            name: L("Vintage"), icon: "camera.aperture",
            style: AIDirectorStyle(
                colorStyle: .vintage,
                transitionPool: [.crossfade, .rotate],
                paceMultiplier: 1.0,
                musicHint: L("Try classic jazz or a retro synth track"),
                musicGenreKeywords: ["Jazz", "Swing"],
                reasoning: nil
            )
        )
    ]
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension AIDirectorEngine.Suggestion {
    var asDirectorStyle: AIDirectorStyle {
        let colorStyle: ColorStyle
        switch look {
        case .none: colorStyle = .none
        case .vintage: colorStyle = .vintage
        case .blackAndWhite: colorStyle = .blackAndWhite
        case .vibrant: colorStyle = .vibrant
        case .cinematic: colorStyle = .cinematic
        case .warm: colorStyle = .warm
        }

        let paceMultiplier: Double
        let transitionPool: Set<TransitionStyle>
        let musicGenreKeywords: [String]
        switch pace {
        case .slow:
            paceMultiplier = 0.8
            transitionPool = [.crossfade, .zoomOut]
            musicGenreKeywords = ["Piano", "Acoustic", "Classical", "Ambient"]
        case .medium:
            paceMultiplier = 1.0
            transitionPool = [.crossfade, .slide, .zoom, .zoomOut]
            musicGenreKeywords = ["Pop", "Soundtrack", "Acoustic"]
        case .fast:
            paceMultiplier = 1.3
            transitionPool = [.zoom, .slideLeft, .slideUp, .slideDown, .diagonal, .squeeze]
            musicGenreKeywords = ["Electronic", "Dance", "Pop", "EDM"]
        }

        return AIDirectorStyle(
            colorStyle: colorStyle,
            transitionPool: transitionPool,
            paceMultiplier: paceMultiplier,
            musicHint: note,
            musicGenreKeywords: musicGenreKeywords,
            reasoning: note
        )
    }
}
#endif
