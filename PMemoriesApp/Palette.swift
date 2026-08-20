import SwiftUI

/// Paleta i motyw wizualny appki — dokładne kolory z brandingu PMemories
/// (#4F8CFF / #6C63FF / #A855F7 / #FFB84D).
enum Palette {
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    static let blue = rgb(0x4F, 0x8C, 0xFF)
    static let indigo = rgb(0x6C, 0x63, 0xFF)
    static let purple = rgb(0xA8, 0x55, 0xF7)
    static let accent = rgb(0xFF, 0xB8, 0x4D)

    /// Stonowane kolory tras Travel Route Overview (18.08.2026) — user na
    /// realnym urządzeniu: surowy systemowy `.red` "tragiczny", zbyt
    /// nasycony na tle satelitarnej mapy. Ręcznie dobrane, MIĘKKIE tony
    /// (ten sam duch co reszta palety marki — `rgb()`, nie systemowe
    /// `.red`/`.pink`/`.yellow`), inspirowane paletą z referencji usera.
    static let coral = rgb(0xFF, 0x6B, 0x6B)
    /// Było `rose` (0xEC6FA6, różowy) — user: "te odcienie różu też mi się
    /// nie podobają" (18.08.2026, ciąg dalszy). Zamiast kolejnego odcienia
    /// z rodziny różu/fioletu (już DWUKROTNIE odrzuconej — najpierw
    /// `Palette.purple`, potem różowy), zupełnie inna rodzina barw: stonowany
    /// turkus, wyraźnie odróżnialny od reszty użytych kolorów (niebieski/
    /// koral/złoto/brąz).
    static let teal = rgb(0x2E, 0xC4, 0xB6)
    static let gold = rgb(0xE8, 0xC5, 0x47)
    static let tan = rgb(0xA6, 0x7C, 0x52)

    static let heroGradient = LinearGradient(
        colors: [blue, indigo, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
