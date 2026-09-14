import Foundation
import CoreLocation
import SwiftData

/// "Travel Time Machine" (`Travel.md`) — Faza 1: kartka "W tym dniu..."
/// pokazująca miejsca odwiedzone dokładnie tego samego dnia (miesiąc+dzień)
/// w poprzednich latach. Bez pogody na tych kartach (05.09.2026, user: "w
/// przeszłym nie potrzebujemy temperatury") — pogoda żyje TYLKO przy
/// aktualnej/nadchodzącej podróży (`currentTemperature`/`forecastTemperature`
/// niżej), gdzie ma praktyczną wartość ("co spakować"), nie przy wspomnieniu
/// sprzed lat. Powiadomienia push świadomie ODŁOŻONE — osobny, większy temat
/// (uprawnienia `UNUserNotificationCenter`, harmonogram w tle).
enum TravelTimeMachineProvider {
    /// Temperatura TERAZ w miejscu bieżącego przystanku trwającej podróży
    /// (05.09.2026, user: "mam Romania 4 of 8, czy może pokazać jaka tam
    /// jest temperatura teraz") — Open-Meteo Forecast (nie Archive, tamten
    /// endpoint jest tylko dla dat z przeszłości), ten sam darmowy/keyless
    /// dostawca. `nil` przy błędzie sieci — appka po prostu nie pokazuje
    /// temperatury zamiast fałszywej wartości.
    static func currentTemperature(at coordinate: CLLocationCoordinate2D) async -> Double? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "current_weather", value: "true"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ForecastResponse.self, from: data) else { return nil }
        return response.current_weather.temperature
    }
}

private struct ForecastResponse: Decodable {
    struct CurrentWeather: Decodable {
        let temperature: Double
    }
    let current_weather: CurrentWeather
}

private struct ForecastDailyResponse: Decodable {
    struct Daily: Decodable {
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
    }
    let daily: Daily
}

extension TravelTimeMachineProvider {
    struct ForecastTemperature {
        let maxC: Double
        let minC: Double
    }

    /// Prognoza (max/min) na KONKRETNY dzień nadchodzącej podróży
    /// (05.09.2026, user: "w nadciągających... dobrze mieć [temperaturę]")
    /// — Open-Meteo Forecast API sięga ~16 dni w przód; poza tym zakresem
    /// (albo offline) po prostu `nil`, appka nie zgaduje. Ten sam endpoint
    /// co `currentTemperature`, tylko z parametrem `daily` zamiast
    /// `current_weather`.
    static func forecastTemperature(at coordinate: CLLocationCoordinate2D, date: Date) async -> ForecastTemperature? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
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
              let response = try? JSONDecoder().decode(ForecastDailyResponse.self, from: data),
              let maxC = response.daily.temperature_2m_max.first ?? nil,
              let minC = response.daily.temperature_2m_min.first ?? nil else { return nil }

        return ForecastTemperature(maxC: maxC, minC: minC)
    }

    /// Jeden dzień w pasku prognozy prowadzącym do dnia wyprawy.
    struct DailyForecast: Identifiable {
        var id: Date { date }
        let date: Date
        let maxC: Double
        let minC: Double
    }

    /// Prognoza DZIEŃ PO DNIU od dziś do `date` włącznie (12.09.2026, user:
    /// "jak miejsce docelowe bedzie np rysy zeby pokazywalo nam tem na
    /// rysach max do dnia wyprawy" — ten sam duch co `forecastTemperature`
    /// dla jednego dnia, tylko cały pasek prowadzący do wyprawy, nie tylko
    /// sam dzień startu). Open-Meteo Forecast sięga ~16 dni w przód — dla
    /// dat dalej appka po prostu zwraca to, na co dostała odpowiedź (może
    /// być pusto), zero zgadywania brakujących dni. `date` w przeszłości →
    /// pusta tablica, appka nie pokazuje nic.
    static func dailyForecasts(at coordinate: CLLocationCoordinate2D, through date: Date) async -> [DailyForecast] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: date)
        guard end >= today else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "start_date", value: formatter.string(from: today)),
            URLQueryItem(name: "end_date", value: formatter.string(from: end)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ForecastDailyRangeResponse.self, from: data) else { return [] }

        return zip(response.daily.time, zip(response.daily.temperature_2m_max, response.daily.temperature_2m_min))
            .compactMap { dateString, temps -> DailyForecast? in
                guard let day = formatter.date(from: dateString), let maxC = temps.0, let minC = temps.1 else { return nil }
                return DailyForecast(date: day, maxC: maxC, minC: minC)
            }
    }
}

/// Jak `ForecastDailyResponse` wyżej, ale z `time` (14.09.2026 — potrzebne
/// żeby dopasować każdą temperaturę do konkretnego dnia zakresu, nie tylko
/// pierwszego elementu jak przy pojedynczym dniu w `forecastTemperature`).
private struct ForecastDailyRangeResponse: Decodable {
    struct Daily: Decodable {
        let time: [String]
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
    let country: String?
    let countryCode: String?
    let coordinate: CLLocationCoordinate2D
    let visitDate: Date
    let yearsAgo: Int
    /// `PersistentIdentifier` całej podróży (05.09.2026) — kilka przystanków
    /// TEJ SAMEJ podróży może pasować do "dziś" naraz (np. lot z przesiadką
    /// zapisany z tą samą datą na starcie i na miejscu docelowym); grupowanie
    /// po tym polu w `onThisDay(from:)` pozwala pokazać JEDNĄ kartę per
    /// podróż zamiast osobnej karty na każdy przystanek.
    let tripID: PersistentIdentifier
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
            // Kilka przystanków TEJ SAMEJ podróży może pasować do "dziś"
            // naraz (05.09.2026, user: realny raport — lotnisko wylotu
            // "London Gatwick Airport" i miejsce docelowe "Sellia"/"Chania"
            // wszystkie zapisane z tą samą datą). Próba pokazania osobnej
            // karty na KAŻDY przystanek (06.09.2026) okazała się zła —
            // user: "to mi pokazuje te same wakacje" — dwie karty jednej
            // podróży to duplikat, nie dwa wspomnienia. Z powrotem JEDNA
            // karta na podróż, ale nadal wybieramy najdalszy PRAWDZIWY
            // przystanek (`order > 0`), nie punkt startowy/lotnisko wylotu
            // (`order == 0`) — fallback na cały zbiór kandydatów tylko gdy
            // jedynym pasującym przystankiem jest sam start.
            let candidates: [(stop: SavedStop, visitDate: Date, yearsAgo: Int)] = trip.stops.compactMap { stop in
                guard !stop.isHiddenFromOnThisDay, let visitDate = stop.arrivalDate else { return nil }
                let visitComponents = calendar.dateComponents([.month, .day, .year], from: visitDate)
                guard visitComponents.month == todayComponents.month, visitComponents.day == todayComponents.day else { return nil }
                let yearsAgo = calendar.component(.year, from: today) - (visitComponents.year ?? calendar.component(.year, from: today))
                guard yearsAgo > 0 else { return nil }
                return (stop, visitDate, yearsAgo)
            }

            // 11.09.2026, user: realny raport — karta "13 lat temu" pokazywała
            // "United Kingdom (London Gatwick Airport)", czyli samo lotnisko
            // wylotu z kraju domowego. "jesli lece z anglii i wracam do anglii
            // to nie ma sensu mi to pokazywac ale jesli lece z anglii gdzies i
            // pozniej wracam to lepiej zeby widziec to gdzie lece a nie zkad
            // wylatuje albo wracam". Więc: pomiń punkt startowy (`order == 0`),
            // lotniska/tranzyt, i przystanki w kraju startu (leg powrotny).
            let originCode = trip.stops.min(by: { $0.order < $1.order }).flatMap {
                TravelAchievementsCalculator.countryGroupingCode(countryCode: $0.countryCode, administrativeArea: $0.administrativeArea)
            }
            func groupingCode(_ stop: SavedStop) -> String? {
                TravelAchievementsCalculator.countryGroupingCode(countryCode: stop.countryCode, administrativeArea: stop.administrativeArea)
            }
            let tripLeavesOriginCountry = originCode != nil && trip.stops.contains { code in
                if let c = groupingCode(code) { return c != originCode }
                return false
            }
            let foreignCandidates = candidates.filter {
                $0.stop.order > 0
                    && !TravelAchievementsCalculator.looksLikeAirport($0.stop.cityName)
                    && (originCode == nil || groupingCode($0.stop) != originCode)
            }
            let pool: [(stop: SavedStop, visitDate: Date, yearsAgo: Int)]
            if !foreignCandidates.isEmpty {
                pool = foreignCandidates
            } else if tripLeavesOriginCountry {
                // dziś pasuje tylko lotnisko / leg powrotny podróży zagranicznej
                // — to nie jest wspomnienie z celu, pomijamy podróż w ogóle.
                continue
            } else {
                // podróż w całości krajowa: pokaż prawdziwy przystanek (nie
                // start, nie lotnisko), inaczej pomiń.
                let domesticCandidates = candidates.filter {
                    $0.stop.order > 0 && !TravelAchievementsCalculator.looksLikeAirport($0.stop.cityName)
                }
                if domesticCandidates.isEmpty { continue }
                pool = domesticCandidates
            }
            guard let best = pool.max(by: { $0.stop.order < $1.stop.order }) else { continue }
            let linkedIDs = Array(Set(trip.stops.compactMap(\.linkedProjectID)))
            matches.append(OnThisDayMatch(
                stopID: best.stop.id, tripTitle: trip.title, cityName: best.stop.cityName,
                country: best.stop.country, countryCode: best.stop.countryCode, coordinate: best.stop.coordinate,
                visitDate: best.visitDate, yearsAgo: best.yearsAgo, tripID: trip.id, linkedProjectIDs: linkedIDs
            ))
        }
        return matches.sorted { $0.yearsAgo < $1.yearsAgo }
    }
}
