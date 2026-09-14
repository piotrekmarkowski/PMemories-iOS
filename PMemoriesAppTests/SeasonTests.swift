import Testing
import Foundation
@testable import PMemories

/// `Season.current` steruje skórką `.seasonal` (AppSkin.swift) — poprawność
/// zależy od dwóch niezależnych rzeczy na raz (miesiąc + półkula), łatwo
/// nieświadomie zepsuć jedną poprawiając drugą. Daty budowane ręcznie przez
/// `DateComponents` w UTC, nie `Date()`/dzisiejsza data — testy muszą dawać
/// ten sam wynik niezależnie od tego, kiedy/gdzie faktycznie się uruchamiają
/// (lokalnie czy na runnerze CI).
struct SeasonTests {
    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Northern hemisphere: June is summer, December is winter")
    func northernHemisphereSeasons() {
        #expect(Season.current(date: utcDate(year: 2026, month: 6, day: 15), regionCode: "PL") == .summer)
        #expect(Season.current(date: utcDate(year: 2026, month: 12, day: 15), regionCode: "PL") == .winter)
    }

    @Test("Southern hemisphere flips the same calendar month to the opposite season")
    func southernHemisphereSeasonsAreFlipped() {
        #expect(Season.current(date: utcDate(year: 2026, month: 6, day: 15), regionCode: "AU") == .winter)
        #expect(Season.current(date: utcDate(year: 2026, month: 12, day: 15), regionCode: "AU") == .summer)
    }

    @Test("No region code defaults to the northern-hemisphere mapping")
    func missingRegionDefaultsToNorthern() {
        #expect(Season.current(date: utcDate(year: 2026, month: 6, day: 15), regionCode: nil) == .summer)
    }

    @Test("All four seasons appear across the year in the northern hemisphere")
    func allFourSeasonsCoveredAcrossYear() {
        #expect(Season.current(date: utcDate(year: 2026, month: 4, day: 1), regionCode: "PL") == .spring)
        #expect(Season.current(date: utcDate(year: 2026, month: 7, day: 1), regionCode: "PL") == .summer)
        #expect(Season.current(date: utcDate(year: 2026, month: 10, day: 1), regionCode: "PL") == .autumn)
        #expect(Season.current(date: utcDate(year: 2026, month: 1, day: 1), regionCode: "PL") == .winter)
    }
}
