import Foundation

/// Wynik "AI Director" (30.08.2026, pierwsza funkcja `Docs/AI.md`) — czy to
/// z realnego modelu AI (`AIDirectorEngine.suggestStyle`) czy z presetu, oba
/// tworzą DOKŁADNIE to samo, bo oba karmią te same, już istniejące ustawienia
/// edytora (`ColorStyle`/`TransitionStyle`/`MediaItem.speed`) — zero osobnej
/// ścieżki renderowania dla wyniku AI.
struct AIDirectorStyle {
    var colorStyle: ColorStyle
    var transitionPool: Set<TransitionStyle>
    /// Mnożnik nakładany na już istniejące `MediaItem.speed` każdego klipu
    /// (NIE na `duration` — długość finalnego filmiku ma zostać dopasowana
    /// do muzyki tak jak dziś, patrz komentarz przy `MediaItem.duration`).
    var paceMultiplier: Double
    /// Podpowiedź tekstowa gatunku/nastroju, pokazywana zawsze.
    var musicHint: String
    /// Słowa kluczowe do przeszukania WŁASNEJ biblioteki usera (31.08.2026,
    /// user: "czy AI moze podpowiadac piosenke jaka mozna dodac do swoich
    /// zdjec") — `MusicLibrarySuggester` dopasowuje je do tagu gatunku
    /// (`MPMediaItemPropertyGenre`) prawdziwych utworów w bibliotece Apple
    /// Music/zakupionych usera. Appka nie ma dostępu do żadnego zewnętrznego
    /// katalogu muzycznego (Spotify/cały Apple Music) — tylko do tego, co
    /// user faktycznie już ma, stąd "podpowiedź", nie gwarancja trafienia.
    var musicGenreKeywords: [String]
    /// Krótkie uzasadnienie z modelu AI, w języku usera — `nil` dla presetów
    /// (tam wybór jest oczywisty z samej nazwy, nic do wyjaśniania).
    var reasoning: String?
}

struct AIDirectorPreset: Identifiable {
    let name: String
    let icon: String
    let style: AIDirectorStyle

    var id: String { name }
}
