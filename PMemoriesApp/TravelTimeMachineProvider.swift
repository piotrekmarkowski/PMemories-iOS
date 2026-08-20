import Foundation
import CoreLocation
import SwiftData

/// "Travel Time Machine" (`Travel.md`: "powiadomienia rocznicowe + pogoda z
/// tamtego dnia") — Faza 1: kartka "W tym dniu..." pokazująca miejsca
/// odwiedzone dokładnie tego samego dnia (miesiąc+dzień) w poprzednich
/// latach, z prawdziwą historyczną pogodą z DNIA WIZYTY (nie dzisiejszą).
/// Powiadomienia push świadomie ODŁOŻONE — to osobny, większy temat
/// (uprawnienia `UNUserNotificationCenter`, harmonogram w tle), nie
/// zaczynać przed tą częścią. Historyczna pogoda: Open-Meteo Archive API,
/// darmowe/keyless dla użytku niekomercyjnego — ten sam wzorzec co
/// `ElevationProvider`/`WaymarkedTrailProvider` (appka nie ma własnego
/// serwera pogodowego).
enum TravelTimeMachineProvider {
    private static let endpoint = "https://archive-api.open-meteo.com/v1/archive"

    struct HistoricalWeather {
        let maxC: Double
        let minC: Double
    }

    /// `nil` gdy zapytanie się nie powiedzie (offline, brak danych dla tej
    /// daty/miejsca) — karta "W tym dniu" pokazuje wtedy samo miejsce+rok
    /// bez pogody, nie chowa całej karty.
    static func historicalWeather(at coordinate: CLLocationCoordinate2D, date: Date) async -> HistoricalWeather? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)

        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "start_date", value: dateString),
            URLQueryItem(name: "end_date", value: dateString),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ArchiveResponse.self, from: data),
              let maxC = response.daily.temperature_2m_max.first ?? nil,
              let minC = response.daily.temperature_2m_min.first ?? nil else { return nil }

        return HistoricalWeather(maxC: maxC, minC: minC)
    }
}

private struct ArchiveResponse: Decodable {
    struct Daily: Decodable {
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
    }
    let daily: Daily
}

/// Jedno trafienie "W tym dniu" — przystanek odwiedzony dokładnie tego
/// samego miesiąca/dnia w przeszłości. `stopID` to `PersistentIdentifier`
/// (SwiftData `@Model` nie ma własnego `UUID id` jak ulotny `TripStop`).
struct OnThisDayMatch: Identifiable {
    var id: PersistentIdentifier { stopID }
    let stopID: PersistentIdentifier
    let tripTitle: String
    let cityName: String
    let countryCode: String?
    let coordinate: CLLocationCoordinate2D
    let visitDate: Date
    let yearsAgo: Int
    /// Filmy już powiązane z TĄ podróżą (dowolny przystanek, ten sam
    /// mechanizm ręcznego łączenia co World Globe, 10.08.2026) — "Create
    /// Memory again" na karcie przenosi wprost do nich zamiast zaczynać od
    /// zera, gdy taki film już istnieje.
    let linkedProjectIDs: [UUID]
}

extension TravelAchievementsCalculator {
    /// Porównuje TYLKO miesiąc+dzień (nie rok) — "5 lat temu, 30 lipca" —
    /// świadomie wyklucza dopasowania z bieżącego roku (`yearsAgo == 0`),
    /// bo "rok temu dzisiaj" nie ma sensu dla podróży sprzed kilku dni w tym
    /// samym roku kalendarzowym... [pozostawione dla przyszłych lat, gdy
    /// user faktycznie ma wielosezonowe dane].
    static func onThisDay(from trips: [SavedTrip], today: Date = Date(), calendar: Calendar = .current) -> [OnThisDayMatch] {
        let todayComponents = calendar.dateComponents([.month, .day], from: today)
        var matches: [OnThisDayMatch] = []
        for trip in trips {
            for stop in trip.stops {
                guard let visitDate = stop.arrivalDate else { continue }
                let visitComponents = calendar.dateComponents([.month, .day, .year], from: visitDate)
                guard visitComponents.month == todayComponents.month, visitComponents.day == todayComponents.day else { continue }
                let yearsAgo = calendar.component(.year, from: today) - (visitComponents.year ?? calendar.component(.year, from: today))
                guard yearsAgo > 0 else { continue }
                let linkedIDs = Array(Set(trip.stops.compactMap(\.linkedProjectID)))
                matches.append(OnThisDayMatch(
                    stopID: stop.id, tripTitle: trip.title, cityName: stop.cityName,
                    countryCode: stop.countryCode, coordinate: stop.coordinate,
                    visitDate: visitDate, yearsAgo: yearsAgo, linkedProjectIDs: linkedIDs
                ))
            }
        }
        return matches.sorted { $0.yearsAgo < $1.yearsAgo }
    }
}
