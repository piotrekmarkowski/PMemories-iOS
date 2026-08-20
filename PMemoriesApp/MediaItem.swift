import Foundation
import PhotosUI
import UIKit

/// Jeden element sekwencji filmiku: zdjęcie, Live Photo albo klip wideo.
struct MediaItem: Identifiable {
    let id = UUID()
    let pickerItemId: String?
    let isLivePhoto: Bool
    let isVideo: Bool
    let thumbnail: UIImage?

    /// Czy dla tego elementu ma być użyty ruch (paired video z Live Photo).
    var useMotion: Bool

    /// Lokalny plik wideo wyciągnięty z Live Photo (nil dla zwykłych zdjęć
    /// albo gdy wyciągnięcie się nie udało).
    var pairedVideoURL: URL?

    /// Lokalny plik wideo dla elementów typu wideo (isVideo == true).
    var videoURL: URL?

    /// Czas wyświetlania w finalnym filmiku (sekundy). Wyliczany na start
    /// przez równy podział długości utworu przez liczbę elementów, chyba że
    /// `isManuallyTrimmed` — wtedy user ustawił to ręcznie w Trim.
    var duration: Double

    /// Punkt startowy w źródłowym klipie (sekundy) — od kiedy zaczyna się
    /// używany fragment wideo/Live Photo. 0 = od początku (domyślnie).
    var trimStart: Double = 0

    /// Długość całego źródłowego klipu (sekundy) — do budowy suwaka Trim.
    /// `nil` dla zwykłych zdjęć (nie ma czego przycinać) albo zanim się wczyta.
    var sourceDuration: Double?

    /// User ręcznie ustawił `duration`/`trimStart` w Trim — automatyczne
    /// rozłożenie czasu po zmianie utworu ma to zostawić w spokoju.
    var isManuallyTrimmed: Bool = false

    /// Mnożnik prędkości odtwarzania (1.0 = normalna, 2.0 = 2x szybciej,
    /// 0.5 = 2x wolniej/slow-mo). `duration` ZOSTAJE czasem wyświetlania w
    /// finalnym filmiku bez zmian — to ile SEKUND ŹRÓDŁA trzeba zużyć, żeby
    /// wypełnić ten czas, liczy `VideoComposer` (`duration * speed`). Dzięki
    /// temu prędkość nie wchodzi w konflikt z Trim/Split/redistribute.
    var speed: Double = 1.0

    /// Dodatkowy obrót w stopniach (0/90/180/270), zgodnie z ruchem
    /// wskazówek zegara — do poprawy błędnej orientacji klipu.
    var rotationDegrees: Int = 0

    /// `false` = "fit" (całość klipu widoczna, ew. czarne pasy),
    /// `true` = "fill" (wypełnia całą klatkę, brzegi mogą być obcięte).
    var cropFill: Bool = false

    /// Głośność oryginalnego dźwięku klipu (0 = wyciszony, 1 = pełna) —
    /// niezależna od głośności muzyki w tle. Ma znaczenie tylko dla klipów
    /// z realnym dźwiękiem (wideo/Live Photo), nie dla zwykłych zdjęć.
    var originalVolume: Double = 1.0

    /// Styl przejścia UŻYWANEGO PRZY WEJŚCIU tego elementu (przejście z
    /// poprzedniego klipu DO tego) — `nil` = auto (appka sama dobiera z puli,
    /// `TransitionStyle.auto(forTransitionIndex:)`), nieużywane dla
    /// pierwszego elementu (nic przed nim nie ma). Ten sam wzorzec co
    /// `rotationDegrees`/`cropFill` — realnie zastosowane w `VideoComposer`,
    /// nie tylko kosmetyka UI.
    var transitionStyle: TransitionStyle?

    /// Karta brandingowa PMemories doklejana na końcu KAŻDEGO eksportu
    /// (12.08.2026, user: "to będzie wstawka już bez muzyki na końcu") —
    /// `true` mówi `VideoComposer`, żeby ścieżka muzyczna zatrzymała się
    /// PRZED tym elementem zamiast ciągnąć się przez cały jego czas trwania
    /// (świadoma cisza, nie bug). Świadomie NIE dotyczy istniejącej karty
    /// "Travel Replay" (ta zostaje jak dziś — część historii podróży, nie
    /// samo logo).
    var mutesBackgroundMusic: Bool = false

    var isTrimmable: Bool {
        (isVideo || (isLivePhoto && useMotion)) && sourceDuration != nil
    }
}
