import Foundation
import UIKit

/// Jeden element nakładki "picture-in-picture" — osobny, mały tor NAD
/// głównym timeline'em. Faza 1 "prawdziwego multi-tracku" (patrz
/// `Docs/Studio.md`) — świadomie wąski zakres: jeden tor, bez nakładających
/// się na siebie nawzajem elementów, stałe pozycje w rogu (nie swobodne
/// przeciąganie), zawsze wyciszone (bez własnego dźwięku).
///
/// Czas liczony WZGLĘDEM CAŁEGO finalnego filmiku (sekundy od startu), NIE
/// względem pozycji w głównej sekwencji — ten sam wzorzec co `Caption`
/// (`startTime`/`endTime`). Pozycje klipów w głównym torze są ulotne
/// (przesuwają się przy każdym reorderze/trimie/splicie/zmianie utworu przez
/// `redistributeDurations()`), więc kotwiczenie nakładki do "klipu numer N"
/// wymagałoby ciągłego przeliczania — globalny czas tego unika.
struct OverlayItem: Identifiable {
    let id = UUID()
    let pickerItemId: String?
    let isLivePhoto: Bool
    let isVideo: Bool
    let thumbnail: UIImage?

    /// Czy użyć ruchu z Live Photo — ten sam mechanizm co `MediaItem.useMotion`.
    var useMotion: Bool
    var pairedVideoURL: URL?
    var videoURL: URL?

    /// Moment (sekundy od startu finalnego filmiku), w którym nakładka się pojawia.
    var globalStartTime: Double

    /// Jak długo nakładka jest widoczna (sekundy). Zawsze odtwarzana od
    /// początku źródła, bez własnego przycinania/prędkości — świadomie poza
    /// zakresem Fazy 1 (patrz plan).
    var duration: Double

    var corner: OverlayCorner = .bottomTrailing

    /// Ułamek SZEROKOŚCI kanwy — pudełko nakładki zachowuje proporcje kanwy
    /// (nie dowolny prostokąt), żeby skalowanie nigdy nie ucinało zdjęć
    /// (patrz `VideoComposer.overlayTransform`).
    var sizeScale: Double = 0.35
}

/// 4 stałe rogi ekranu — świadomie bez swobodnego przeciągania w Fazie 1.
enum OverlayCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    var id: String { rawValue }
}
