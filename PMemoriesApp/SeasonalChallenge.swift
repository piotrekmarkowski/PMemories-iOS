import Foundation

/// "Sezonowe wyzwania" nad Rankingiem — TODO.md 09.08.2026 (obszerny feedback
/// zewnętrzny o retencji): "powód do wracania do appki nawet bez nowej
/// podróży w trakcie". Świadomie TYLKO dwa proste, uczciwie policzalne cele
/// z już śledzonych danych (`SavedTrip`/`SavedProject`) — zero nowej bazy,
/// zero persystencji stanu, zero zgadywania (ta sama zasada co reszta
/// appki — np. brak wymyślonej liczby zdjęć w `RecentMemoryTile`).
enum SeasonalChallenge {
    struct Progress {
        let seasonLabel: String
        let year: Int
        let newCountriesTarget: Int
        let newCountriesDone: Int
        let newMemoriesTarget: Int
        let newMemoriesDone: Int

        var isComplete: Bool {
            newCountriesDone >= newCountriesTarget && newMemoriesDone >= newMemoriesTarget
        }
    }

    /// "Nowy kraj" = kraj odwiedzony W OKNIE sezonu, którego NIE było w
    /// żadnej podróży PRZED początkiem sezonu — powrót do kraju już
    /// wcześniej odwiedzonego się nie liczy, żeby wyzwanie faktycznie
    /// nagradzało coś nowego, nie powtórkę.
    static func currentProgress(trips: [SavedTrip], projects: [SavedProject], date: Date = Date()) -> Progress {
        let season = Season.current(date: date)
        let start = Season.currentRangeStart(date: date)

        var countriesBefore: Set<String> = []
        var countriesDuringSeason: Set<String> = []
        for trip in trips {
            for stop in trip.stops {
                guard let code = stop.countryCode, let visit = stop.arrivalDate else { continue }
                if visit < start {
                    countriesBefore.insert(code)
                } else if visit <= date {
                    countriesDuringSeason.insert(code)
                }
            }
        }
        let newCountries = countriesDuringSeason.subtracting(countriesBefore).count

        let newMemories = projects.filter { $0.createdAt >= start && $0.createdAt <= date }.count

        return Progress(
            seasonLabel: season.displayName,
            year: Calendar.current.component(.year, from: date),
            newCountriesTarget: 1, newCountriesDone: min(newCountries, 1),
            newMemoriesTarget: 2, newMemoriesDone: min(newMemories, 2)
        )
    }
}
