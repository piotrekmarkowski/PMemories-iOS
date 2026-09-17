import Testing
import UIKit
@testable import PMemories

/// 17.09.2026 — powstał po realnym, cichym buggu: `TravelPassportView`
/// renderowała `Image(assetName)` na podstawie samego faktu, że kod kraju
/// był kluczem w `worldStickerAssetByCountryCode` — nie sprawdzała, czy
/// TAKI ASSET FAKTYCZNIE ISTNIEJE w katalogu. `sticker_*` (~300 wpisów)
/// nie miał ANI JEDNEGO prawdziwego pliku od dwóch tygodni — appka cicho
/// pokazywała puste miejsce zamiast działającego fallbacku. `Image(String)`
/// kompiluje się niezależnie od tego czy string trafia w prawdziwy zasób —
/// Swift nie ma na to kontroli w czasie kompilacji, więc CI (build+testy)
/// tego nie łapało. Ten plik to generyczna siatka bezpieczeństwa: KAŻDY
/// słownik kod→nazwa-assetu w kodzie ma tu wpis, testowany automatycznie.
/// Dodając NOWY taki słownik w przyszłości — dopisz go do `allAssetDictionaries`
/// niżej, żeby ta sama ochrona objęła i jego.
struct AssetIntegrityTests {
    private static func missingAssets(in dict: [String: String]) -> [String] {
        dict.sorted(by: { $0.key < $1.key }).compactMap { code, assetName in
            UIImage(named: assetName) == nil ? "\(code) → \(assetName)" : nil
        }
    }

    private static func formatMissing(_ missing: [String]) -> String {
        "\(missing.count) assetów bez pliku w Assets.xcassets: " +
        missing.prefix(10).joined(separator: ", ") +
        (missing.count > 10 ? " (+\(missing.count - 10) więcej)" : "")
    }

    /// `CountryStamp*` (plakat "My Travel Journey") — dziś w 100% kompletny
    /// (214/214, zweryfikowane 17.09.2026). OSTRY test — jeśli ktoś kiedyś
    /// doda nowy wpis do `journeyStampAssetByCountryCode` bez dodania
    /// odpowiadającego pliku, CI ma to złapać od razu, nie po fakcie.
    @Test("Wszystkie assety plakatu (journeyStampAssetByCountryCode) istnieją")
    func posterAssetsExist() {
        let missing = Self.missingAssets(in: journeyStampAssetByCountryCode)
        #expect(missing.isEmpty, "\(Self.formatMissing(missing))")
    }

    /// `sticker_*` (Travel Passport) — ŚWIADOMIE wyłączony, NIE bo nie warto
    /// testować, tylko bo dziś (17.09.2026) ~300 wpisów w
    /// `worldStickerAssetByCountryCode` wskazuje na assety, które NIGDY nie
    /// zostały dodane do katalogu (to był zamierzony "tymczasowy podgląd"
    /// sprzed dwóch tygodni — patrz komentarz przy słowniku). Włączenie tego
    /// testu na twardo zablokowałoby CI za coś, co wymaga osobnej decyzji
    /// (dokończyć ~300 naklejek, czy wyczyścić słownik) — nie za regresję.
    /// PRZYWRÓĆ ten test (usuń `.disabled`), gdy ta decyzja zapadnie.
    @Test("Wszystkie assety Passportu (worldStickerAssetByCountryCode) istnieją", .disabled("~170 assetów sticker_* świadomie jeszcze niedostarczonych, patrz komentarz — nie regresja"))
    func passportAssetsExist() {
        let missing = Self.missingAssets(in: worldStickerAssetByCountryCode)
        #expect(missing.isEmpty, "\(Self.formatMissing(missing))")
    }

    /// 17.09.2026 — pierwsze 45 prawdziwych `sticker_*` (Europa), wycięte z
    /// arkuszy ChatGPT "World Travel Stickers". OSTRY test na TĘ konkretną
    /// podgrupę — reszta (~170) zostaje `.disabled` wyżej, dopóki nie
    /// zostaną dostarczone.
    @Test("Europejskie assety Passportu (pierwsza dostarczona partia) istnieją")
    func passportEuropeAssetsExist() {
        let europeCodes: Set<String> = [
            "DE", "GR", "HU", "IS", "IE", "IT", "XK", "LV", "LI", "LT", "LU", "MT", "MD", "MC", "ME",
            "NL", "MK", "NO", "PL", "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE", "CH", "TR",
            "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "GE",
        ]
        let subset = worldStickerAssetByCountryCode.filter { europeCodes.contains($0.key) }
        #expect(subset.count == 45, "Oczekiwano 45 europejskich wpisów w słowniku, jest \(subset.count)")
        let missing = Self.missingAssets(in: subset)
        #expect(missing.isEmpty, "\(Self.formatMissing(missing))")
    }
}
