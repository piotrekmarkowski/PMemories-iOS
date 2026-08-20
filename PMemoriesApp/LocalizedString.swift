import Foundation

/// String Catalogi automatycznie tłumaczą tylko literały przekazane wprost
/// do `Text("...")`/`Label("...")` itp. — stringi które żyją jako dane w
/// modelu (np. `Achievement.title`, `TransportMode.label`) i trafiają do UI
/// przez zmienną (`Text(achievement.title)`) NIE są tłumaczone automatycznie
/// (SwiftUI traktuje `Text(String)` jako verbatim). `L(_:)` robi ręczny
/// lookup w String Catalogu w miejscu KONSTRUKCJI stringa — dzięki temu
/// dowolny call site (`Text`, `.navigationTitle`, string interpolation)
/// dostaje już przetłumaczony tekst, bez zmian po stronie widoku.
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}

/// Czy aktywny język to polski — sprawdza FAKTYCZNIE rozwiązany język
/// (`Bundle.main.preferredLocalizations`), NIE `AppLanguage.current`, bo
/// ten zwraca `.system` gdy user nigdy ręcznie nie wybrał języka w Profile
/// (normalny stan dla większości testerów polegających na domyślnym
/// języku systemu) — odkryte 10.08.2026 przy karcie "Twoja podróż" na Home.
var isPolishLanguageActive: Bool {
    Bundle.main.preferredLocalizations.first == "pl"
}

/// Polska ma TRZY formy liczby mnogiej (1 / 2-4 / 5+), angielski (i
/// uproszczony wzorzec appki `L(...)`-jako-sufiks) tylko dwie — appka w
/// większości miejsc pokazuje zawsze TĘ SAMĄ formę niezależnie od liczby
/// (poprawną tylko dla 2-4, np. "7 Kraje" zamiast "7 Krajów"). Reguła
/// mod10/mod100 — stosować TYLKO gdy `isPolishLanguageActive` (jedyny
/// język appki na bieżąco testowany na żywo przez usera). Pozostałe 26
/// języków mają uproszczony wzorzec jak dotąd — pełna, systemowa naprawa
/// (Xcode String Catalog "plural variations") to osobny, większy temat
/// zapisany w `Docs/TODO.md`, nie robimy tego wszędzie na raz.
func polishPlural(_ count: Int, one: String, few: String, many: String) -> String {
    let mod10 = count % 10
    let mod100 = count % 100
    if count == 1 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

/// "X nights" z polską odmianą — wyciągnięte z `PlannedStopRow` (11.08.2026)
/// żeby ten sam tekst dało się pokazać też w `PlannedTripDetailView`'s
/// podglądzie bez duplikowania logiki.
func nightsText(_ nights: Int) -> String {
    if isPolishLanguageActive {
        return polishPlural(nights, one: "1 noc", few: "\(nights) noce", many: "\(nights) nocy")
    }
    return nights == 1 ? L("1 night") : "\(nights) \(L("nights"))"
}
