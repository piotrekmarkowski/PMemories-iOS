import Testing
import Foundation
@testable import PMemories

/// `SolarTime.sunriseSunset` napędza dzień/nocny wygląd mapy na plakacie
/// podróży (13.09.2026) — czysta, offline matematyka (wzór "Sunrise
/// equation"), więc w pełni testowalna bez sieci/GPS.
struct SolarTimeTests {
    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("Sunrise is before sunset for an ordinary mid-latitude location")
    func sunriseBeforeSunsetAtMidLatitude() throws {
        // Warszawa, przesilenie letnie — zwyczajny, nieproblematyczny dzień.
        let result = SolarTime.sunriseSunset(latitude: 52.23, longitude: 21.01, date: utcDate(year: 2026, month: 6, day: 21))
        let times = try #require(result)
        #expect(times.sunrise < times.sunset)
    }

    @Test("Sunrise-to-sunset window is a plausible single-digit-hours daylight span")
    func daylightSpanIsPlausible() throws {
        let result = SolarTime.sunriseSunset(latitude: 52.23, longitude: 21.01, date: utcDate(year: 2026, month: 6, day: 21))
        let times = try #require(result)
        let hours = times.sunset.timeIntervalSince(times.sunrise) / 3600
        // Warszawa w czerwcu ma dzień ok. 16-17h — szeroki, wyrozumiały
        // zakres (10-20h), żeby test sprawdzał "sensowna liczba", nie
        // dokładną wartość co do minuty (to nie jest kalkulator nawigacyjny).
        #expect(hours > 10 && hours < 20)
    }

    @Test("Polar night (no sunrise at all) returns nil instead of a bogus time")
    func polarNightReturnsNil() {
        // Longyearbyen (Svalbard), ok. 78°N, głęboka zima — słońce w ogóle
        // nie wschodzi. Formuła musi się świadomie poddać (`cosH` poza
        // zakresem -1...1), nie zwrócić przekłamaną godzinę.
        let result = SolarTime.sunriseSunset(latitude: 78.22, longitude: 15.65, date: utcDate(year: 2026, month: 12, day: 21))
        #expect(result == nil)
    }

    @Test("Midnight sun (no sunset at all) also returns nil")
    func midnightSunReturnsNil() {
        let result = SolarTime.sunriseSunset(latitude: 78.22, longitude: 15.65, date: utcDate(year: 2026, month: 6, day: 21))
        #expect(result == nil)
    }
}
