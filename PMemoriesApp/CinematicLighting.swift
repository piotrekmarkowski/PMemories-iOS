import Foundation
import SwiftUI
import CoreLocation

/// "Cinematic Lighting" Faza 1 (`Travel.md`) — mapa dostosowuje oświetlenie
/// do PORY DNIA/ROKU W DANYM MIEJSCU I MOMENCIE PODRÓŻY, nie do zegara
/// widza. Faza 1 = fundament + tint w żywym podglądzie (`TravelMapAnimationView`).
/// Eksport wideo (Faza 2) świadomie odłożony na kolejną sesję — user
/// 30.07.2026: nie ryzykować zmian w obu pipeline'ach (podgląd + eksport)
/// naraz.
///
/// **Znane uproszczenie (świadome, do doprecyzowania później)**: appka nie
/// robi realnego przeliczenia strefy czasowej dla przystanku — godzina
/// wpisana w `DatePicker` traktowana jest wprost jako "czas lokalny w tym
/// miejscu" (bez korekty długości geograficznej/strefy). Dla klasyfikacji
/// Dzień/Golden/Blue/Noc (pasma szerokie na kilkadziesiąt minut do godzin)
/// to wystarczające przybliżenie w praktyce, ale świadomie NIE jest to
/// astronomicznie dokładne dla sekundowej precyzji.
enum LightingCondition: String {
    case day, goldenHour, blueHour, night

    var emoji: String {
        switch self {
        case .day: return "☀️"
        case .goldenHour: return "🌅"
        case .blueHour: return "🌆"
        case .night: return "🌙"
        }
    }

    var label: String {
        switch self {
        case .day: return "Day"
        case .goldenHour: return "Golden Hour"
        case .blueHour: return "Blue Hour"
        case .night: return "Night"
        }
    }

    /// Kolor tintu do nałożenia na mapę — Faza 2 (eksport) użyje tego
    /// samego, żeby podgląd i eksport wyglądały identycznie (ta sama zasada
    /// WYSIWYG co reszta Travel Cinematic Engine).
    var tintColor: Color {
        switch self {
        case .day: return .clear
        case .goldenHour: return Color(red: 1.0, green: 0.72, blue: 0.35)
        case .blueHour: return Color(red: 0.25, green: 0.35, blue: 0.65)
        case .night: return Color(red: 0.05, green: 0.08, blue: 0.25)
        }
    }

    var tintOpacity: Double {
        switch self {
        case .day: return 0
        case .goldenHour: return 0.18
        case .blueHour: return 0.22
        case .night: return 0.38
        }
    }
}

enum SeasonalCondition {
    case none, snow, autumn

    var emoji: String? {
        switch self {
        case .none: return nil
        case .snow: return "❄️"
        case .autumn: return "🍂"
        }
    }
}

enum CinematicLighting {
    /// Wysokość słońca nad horyzontem (stopnie) — standardowy uproszczony
    /// wzór astronomiczny (deklinacja słoneczna + kąt godzinny), ten sam
    /// rodzaj obliczeń co odrzucony wcześniej pomysł "terminatora", ale
    /// użyty TYLKO do klasyfikacji jednego punktu, nie rysowania granicy na
    /// globusie (`Travel.md`, decyzja 27.07.2026).
    static func solarAltitudeDegrees(latitude: Double, longitude: Double, date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return 0 }
        let hour = Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60

        let declinationRad = -23.44 * .pi / 180 * cos(2 * .pi / 365 * (Double(dayOfYear) + 10))
        // Kąt godzinny — bez korekty równania czasu/strefy (świadome
        // uproszczenie opisane w komentarzu na górze pliku).
        let hourAngleRad = (15 * (hour - 12)) * .pi / 180
        let latitudeRad = latitude * .pi / 180

        let sinAltitude = sin(latitudeRad) * sin(declinationRad) + cos(latitudeRad) * cos(declinationRad) * cos(hourAngleRad)
        return asin(max(-1, min(1, sinAltitude))) * 180 / .pi
    }

    /// Progi zgodne z powszechnie przyjętymi definicjami golden/blue hour
    /// (cywilny zmierzch/świt) — nie zmyślone wartości.
    static func condition(latitude: Double, longitude: Double, date: Date) -> LightingCondition {
        let altitude = solarAltitudeDegrees(latitude: latitude, longitude: longitude, date: date)
        switch altitude {
        case 6...: return .day
        case -4..<6: return .goldenHour
        case -6..<(-4): return .blueHour
        default: return .night
        }
    }

    /// Pora roku po miesiącu, świadoma półkuli (ujemna szerokość = południowa
    /// — sezony odwrócone względem północnej) — prawdziwa reguła
    /// kalendarzowa, nie zgadywanie.
    static func seasonalCondition(latitude: Double, date: Date) -> SeasonalCondition {
        let month = Calendar.current.component(.month, from: date)
        let isNorthernHemisphere = latitude >= 0
        let winterMonths: Set<Int> = isNorthernHemisphere ? [12, 1, 2] : [6, 7, 8]
        let autumnMonths: Set<Int> = isNorthernHemisphere ? [9, 10, 11] : [3, 4, 5]
        if winterMonths.contains(month) { return .snow }
        if autumnMonths.contains(month) { return .autumn }
        return .none
    }
}
