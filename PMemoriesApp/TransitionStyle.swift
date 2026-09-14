import Foundation

/// Styl przejścia między dwoma sąsiednimi klipami — user 31.07.2026: dziś
/// appka ma tylko JEDEN, stały crossfade, chce różnorodność ("różne
/// przejścia w filmiku będzie dużo ciekawszy"). Świadomie ograniczone do
/// stylów wykonalnych przez zwykłe rampy `AVMutableVideoCompositionLayer
/// Instruction` (opacity/transform) — TE SAME dwa tory wideo co dzisiejszy
/// crossfade (`VideoComposer.buildInstructions`), zero custom
/// `AVVideoCompositing` (ten temat świadomie odrzucony wcześniej jako
/// "wszystko albo nic", patrz `Docs/TODO.md`/`HISTORIA.md`). Zaczynamy od
/// małej puli (3 style łącznie z crossfade) zamiast rozbudowanego zestawu.
enum TransitionStyle: String, CaseIterable, Identifiable, Codable {
    case crossfade
    case slide
    case zoom
    // Rozbudowane 09.08.2026 do 10 stylów (user: "mamy teraz 3, pasuje
    // zrobić więcej, do 10") — TA SAMA technika co powyższe trzy (rampy
    // opacity/transform), zero custom compositora. `rawValue` nowych
    // przypadków NIE koliduje z niczym już zapisanym (SwiftData), więc
    // stare projekty z `slide`/`zoom` w `transitionStyleRawValue` działają
    // bez zmian.
    case slideLeft
    case slideUp
    case slideDown
    case zoomOut
    case rotate
    case squeeze
    case diagonal
    // Premium (30.08.2026, user: "wprowadz jako premium") — widoczne w
    // Style jako osobna, zablokowana sekcja (kłódka), appka nie ma jeszcze
    // płatności, więc na razie NIE da się ich wybrać (patrz `isPremium`),
    // ale kod/renderowanie stoją gotowe pod przyszły paywall. `.whipPan` to
    // ta sama technika co powyższe 10 (transform ramp) — reszta to DRUGI,
    // opcjonalny przebieg CIFilter w oknie przejścia (patrz
    // `PremiumTransitionEffect`/`PremiumTransitionGrader`), bo efekty typu
    // rozmycie/glitch/light leak wymagają operacji na pikselach, nie tylko
    // transformu/przezroczystości — bez otwierania tematu pełnego custom
    // `AVVideoCompositing` (dalej świadomie odrzucone jako "wszystko albo
    // nic"), bo ten drugi przebieg działa na JUŻ spłaszczonym, wyrenderowanym
    // pliku (dokładnie jak `ColorGrader`), nie na żywej kompozycji.
    case whipPan
    case flash
    case blurDissolve
    case lightLeak
    case glitch

    var id: String { rawValue }

    /// `true` = wymaga przyszłego systemu płatności, dziś widoczne w Style
    /// ale zablokowane (kłódka) — patrz `StyleView`.
    var isPremium: Bool {
        switch self {
        case .whipPan, .flash, .blurDissolve, .lightLeak, .glitch: return true
        default: return false
        }
    }

    /// `nil` = przejście renderowane WYŁĄCZNIE w pierwszym przebiegu
    /// (transform/opacity ramp, jak wszystkie pozostałe style) — dotyczy też
    /// `.whipPan` mimo `isPremium == true`. Pozostałe premium style dokładają
    /// TEN efekt jako DRUGI przebieg (`PremiumTransitionGrader`) NAD bazowym
    /// crossfade z pierwszego przebiegu (patrz `VideoComposer.applyTransition`).
    var premiumEffect: PremiumTransitionEffect? {
        switch self {
        case .flash: return .flash
        case .blurDissolve: return .blurDissolve
        case .lightLeak: return .lightLeak
        case .glitch: return .glitch
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .crossfade: return L("Crossfade")
        // Przemianowane z "Slide" na "Slide Right" przy okazji dodania
        // wariantów kierunkowych — sama etykieta (NIE `rawValue`) więc
        // zero wpływu na już zapisane projekty.
        case .slide: return L("Slide Right")
        case .zoom: return L("Zoom In")
        case .slideLeft: return L("Slide Left")
        case .slideUp: return L("Slide Up")
        case .slideDown: return L("Slide Down")
        case .zoomOut: return L("Zoom Out")
        case .rotate: return L("Rotate")
        case .squeeze: return L("Squeeze")
        case .diagonal: return L("Diagonal")
        case .whipPan: return L("Whip Pan")
        case .flash: return L("Flash")
        case .blurDissolve: return L("Blur Dissolve")
        case .lightLeak: return L("Light Leak")
        case .glitch: return L("Glitch")
        }
    }

    /// Kolejność auto-doboru (`MediaItem.transitionStyle == nil`) — cykliczne
    /// przypisanie po indeksie przejścia, deterministyczne (nie losowe), żeby
    /// ten sam projekt zawsze wyglądał tak samo między eksportami.
    ///
    /// `pool` — 09.08.2026, user: "użytkownik sobie wybiera jakie przejścia
    /// chce i ile, program automatycznie sam je rozmieszcza" — appka cykluje
    /// TYLKO po stylach zaznaczonych w Style (`SavedProject.
    /// enabledTransitionStylesRaw`), nie po całym `allCases`. Pusty/nieprawidłowy
    /// `pool` (np. wszystko odznaczone przez pomyłkę) ma bezpieczny fallback
    /// na pełną pulę, żeby eksport nigdy nie ubił się brakiem stylu.
    static func auto(forTransitionIndex index: Int, pool: [TransitionStyle] = allCases) -> TransitionStyle {
        let safePool = pool.isEmpty ? allCases.filter { !$0.isPremium } : pool
        return safePool[index % safePool.count]
    }
}
