import Testing
@testable import PMemories

/// Regresyjne testy dla `TravelAchievementsCalculator.countryGroupingCode`/
/// `countryGroupingDisplayName` — 13.09.2026, user zgłosił że "Northern
/// Ireland" nie tłumaczyło się na polski (i pozostałe 26 języków), mimo że
/// reszta appki tłumaczyła się poprawnie. Przyczyna: te 4 regiony UK są
/// jedynym miejscem w appce, gdzie nazwa "kraju" nie idzie przez systemową
/// bazę `Locale.localizedString(forRegionCode:)` (UK nie ma osobnych kodów
/// ISO dla Anglii/Szkocji/Walii/Irlandii Północnej) — łatwo znowu przeoczyć
/// przy przyszłej zmianie, stąd test zamiast polegania na ręcznym
/// sprawdzaniu.
struct TravelAchievementsCalculatorTests {
    @Test("UK regions map to distinct GB-XXX codes, not plain GB")
    func ukRegionsGetDistinctCodes() {
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: "England") == "GB-ENG")
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: "Scotland") == "GB-SCT")
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: "Wales") == "GB-WLS")
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: "Northern Ireland") == "GB-NIR")
    }

    @Test("Unrecognized administrativeArea for GB falls back to plain GB, not a guess")
    func ukUnknownRegionFallsBackToPlainCode() {
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: nil) == "GB")
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "GB", administrativeArea: "Some Unknown Place") == "GB")
    }

    @Test("Non-UK countries are untouched by the UK special-casing")
    func nonUKCountriesUnaffected() {
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "FR", administrativeArea: nil) == "FR")
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: "PL", administrativeArea: "Mazowieckie") == "PL")
    }

    @Test("Missing countryCode returns nil, never a made-up code")
    func missingCountryCodeReturnsNil() {
        #expect(TravelAchievementsCalculator.countryGroupingCode(countryCode: nil, administrativeArea: nil) == nil)
    }

    /// Nie sprawdzamy DOKŁADNEJ wartości (localizacja zależy od języka
    /// symulatora/runnera CI, kruche) — sprawdzamy że gałąź regionu UK
    /// FAKTYCZNIE się wykonała (nie spadła cicho na `fallback`), co było
    /// źródłem zgłoszonego buga: cztery regiony UK muszą zwrócić coś INNEGO
    /// niż jawnie zły fallback.
    @Test("UK region display name takes the dedicated branch, not the generic fallback")
    func ukRegionDisplayNameSkipsFallback() {
        let result = TravelAchievementsCalculator.countryGroupingDisplayName(
            countryCode: "GB", administrativeArea: "Northern Ireland", fallback: "WRONG-FALLBACK-VALUE"
        )
        #expect(result != "WRONG-FALLBACK-VALUE")
        #expect(!result.isEmpty)
    }
}
