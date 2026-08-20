import Foundation

/// Jeden napis nałożony na film — czas (sekundy w finalnym filmiku, nie w
/// pojedynczym klipie) + tekst + pozycja. Odpowiednik `MediaItem` dla
/// napisów: ulotna struktura edytowana w `EditView`/`CaptionsView`,
/// zapisywana trwale jako `SavedCaption`.
struct Caption: Identifiable, Equatable {
    let id = UUID()
    var text: String = ""
    var startTime: Double = 0
    var endTime: Double = 3
    var position: CaptionPosition = .bottom
    var font: CaptionFont = .helvetica
    /// "Share with Family" (TODO.md, dopisane 30.07.2026) — dodatkowe
    /// tłumaczenia TEGO SAMEGO napisu, wypalane RAZEM z oryginałem w jednym
    /// eksporcie (nie zamiana języka appki — widz od razu widzi kilka
    /// wersji naraz). Klucz = kod języka (`AppLanguage.rawValue`, np. "pl").
    var translations: [String: String] = [:]
}

enum CaptionPosition: String, CaseIterable, Identifiable {
    case top, center, bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return L("Top")
        case .center: return L("Center")
        case .bottom: return L("Bottom")
        }
    }
}

/// Kilka dopracowanych czcionek zamiast pełnej listy systemowej — user
/// wybiera "styl", nie grzebie w dziesiątkach nazw. Nazwy PostScript muszą
/// dokładnie odpowiadać temu co `CATextLayer`/`UIFont` rozpozna.
enum CaptionFont: String, CaseIterable, Identifiable, Codable {
    case helvetica = "Helvetica-Bold"
    case avenir = "AvenirNext-Bold"
    case georgia = "Georgia-Bold"
    case futura = "Futura-Bold"
    case chalkboard = "ChalkboardSE-Bold"
    case typewriter = "AmericanTypewriter-Bold"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .helvetica: return L("Classic")
        case .avenir: return L("Modern")
        case .georgia: return L("Elegant")
        case .futura: return L("Cinematic")
        case .chalkboard: return L("Playful")
        case .typewriter: return L("Retro")
        }
    }
}
