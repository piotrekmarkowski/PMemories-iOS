import CloudKit

/// Ranking testerów (02.08.2026) — jeden wpis per user w PUBLICZNEJ bazie
/// CloudKit (`iCloud.com.piotrmarkowski.pmemories`), identyfikowany przez
/// stabilny identyfikator Sign in with Apple (`AuthManager`). Wynik to
/// wprost `ExplorerScore.total` (`TravelAchievements.swift`) — user:
/// "ranking ma byc na podstawie punktow, przebytych kilometrow, krajow,
/// miest albo wzniesienia" — dokładnie te składowe już liczy Explorer
/// Score, zero potrzeby nowego wzoru.
/// Wyciąga surowe liczby (km/kraje/miasta/wzniesienie) z gotowego już
/// `ExplorerScore` zamiast liczyć je jeszcze raz osobno — odwraca znane
/// mnożniki z `TravelAchievementsCalculator.explorerScore` (countries×20,
/// cities×5, distance÷100, elevation÷100). Przybliżone (odwrócenie
/// zaokrąglonych punktów), ale to tylko liczby POMOCNICZE do wyświetlenia
/// obok wyniku w rankingu — sam wynik (`score.total`) zostaje dokładny.
extension ExplorerScore {
    var rawCountries: Int { Int((components.first { $0.id == "countries" }?.points ?? 0) / 20) }
    var rawCities: Int { Int((components.first { $0.id == "cities" }?.points ?? 0) / 5) }
    /// `rawKm` USUNIĘTE 13.08.2026 — user: "dlaczego w rankingu pokazuje
    /// 40000 km a na pierwszej stronie 39,955?". Liczyło dystans z
    /// ZAOKRĄGLONYCH punktów (`points × 100`, gdzie `points` to `(totalKm /
    /// 100).rounded()`) — celowo zgrubne dla punktacji, ale realnie
    /// pokazywało w rankingu inną liczbę km niż wszędzie indziej w appce.
    /// Wołający używa teraz `score.totalKm` (dokładny dystans, dodany na
    /// `ExplorerScore` obok punktów).
    var rawElevationM: Double { (components.first { $0.id == "elevation" }?.points ?? 0) * 100 }
}

enum LeaderboardService {
    private static let container = CKContainer(identifier: "iCloud.com.piotrmarkowski.pmemories")
    private static var publicDB: CKDatabase { container.publicCloudDatabase }
    private static let recordType = "LeaderboardEntry"

    enum ServiceError: Error {
        case notSignedIn
    }

    /// 15.09.2026 — user zgłosił zrzut ekranu z surowym błędem CloudKit
    /// wprost w UI ("Error saving record <CKRecordID:...> to server: WRITE
    /// operation not permitted") — `LeaderboardView` pokazywała
    /// `error.localizedDescription` bez żadnego tłumaczenia, więc user
    /// widział techniczny zrzut zamiast zrozumiałego komunikatu.
    ///
    /// `.permissionFailure` w TYM konkretnym miejscu (upsert własnego
    /// wyniku) ma jedną realną przyczynę: rekord o tym `recordName`
    /// (identyfikator Sign in with Apple) w publicznej bazie CloudKit ma
    /// zapisanego INNEGO twórcę (`GRANT WRITE TO "_creator"` w schemacie —
    /// świadomy, prawidłowy wybór bezpieczeństwa: nikt nie powinien móc
    /// nadpisać cudzego wyniku). Dzieje się to gdy TEN SAM Apple ID posłużył
    /// do "Sign in with Apple" na urządzeniu/w momencie, gdy faktyczne konto
    /// iCloud tego urządzenia było inne niż teraz (np. testowanie na
    /// pożyczonym/współdzielonym urządzeniu, albo zmiana konta iCloud po
    /// wcześniejszym zalogowaniu) — appka nie ma jak sama tego naprawić
    /// (nie może przejąć cudzego rekordu), stąd jasny komunikat zamiast
    /// cichej próby ponowienia, która i tak zawsze zawiedzie z tym samym
    /// identyfikatorem.
    static func friendlyMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        switch ckError.code {
        case .permissionFailure:
            return L("This score can't be saved under your current Apple ID — it looks like it was already created by a different iCloud account. Contact the developer if this keeps happening.")
        case .notAuthenticated:
            return L("Sign in to iCloud in Settings to use the Ranking.")
        case .networkUnavailable, .networkFailure:
            return L("No internet connection — try again once you're back online.")
        default:
            return error.localizedDescription
        }
    }

    /// Zapisuje/aktualizuje wynik AKTUALNEGO usera (upsert po stałym ID) —
    /// wołane po każdym przeliczeniu `ExplorerScore` (patrz `AchievementsView`),
    /// nie na jakimś osobnym timerze — zawsze najświeższy stan.
    static func submitCurrentScore(score: ExplorerScore, km: Double, countries: Int, cities: Int, elevationM: Double, avatarFrame: String) async throws {
        guard let userIdentifier = await AuthManager.shared.userIdentifier,
              let displayName = await AuthManager.shared.displayName else {
            throw ServiceError.notSignedIn
        }
        let recordID = CKRecord.ID(recordName: userIdentifier)
        let record: CKRecord
        if let existing = try? await publicDB.record(for: recordID) {
            // Nie nadpisuj WYŻSZEGO wyniku niższym — bug znaleziony
            // 09.08.2026: appka na Macu (bez lokalnych danych podróży,
            // bo appka NIE synchronizuje tras między iPhone/Mac — każda
            // platforma ma OSOBNĄ lokalną bazę) automatycznie nadpisała
            // prawdziwy wynik 398 usera zerem zaraz po zalogowaniu.
            // Urządzenie z mniej kompletną lokalną historią nie powinno
            // NIGDY obniżać już zapisanego wyniku — bierzemy zawsze
            // wyższy z dwóch, nie ostatni zapisany.
            if let existingScore = existing["score"] as? Double, existingScore > score.total {
                return
            }
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["displayName"] = displayName as CKRecordValue
        // Sama RAMKA (kolor/ikona), NIE zdjęcie (30.08.2026, user: "zostawmy
        // tylko ramkę i inicjały narazie" — po tym jak zapytał o cudze
        // zdjęcia w rankingu, świadomie odrzucone: appka nie ma dziś
        // opt-in na pokazywanie zdjęcia profilowego publicznie wszystkim
        // testerom, to osobna decyzja na później). String zamiast enuma —
        // CloudKit i tak nie zna `AvatarFrame`; sezonowe ramki `#if DEBUG`
        // wysłane przez kogoś na buildzie deweloperskim po prostu spadają
        // do `.none` na czyjejś przeglądarce Release (`AvatarFrame(rawValue:)`
        // nie rozpozna nieistniejącego case'a), bezpiecznie.
        record["avatarFrame"] = avatarFrame as CKRecordValue
        record["score"] = score.total as CKRecordValue
        record["km"] = km as CKRecordValue
        record["countries"] = countries as CKRecordValue
        record["cities"] = cities as CKRecordValue
        record["elevationM"] = elevationM as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try await publicDB.save(record)
    }

    /// Top N wg wyniku malejąco (domyślnie) lub wg liczby krajów malejąco
    /// (10.08.2026 — TODO.md, alternatywa dla samych punktów: "ranking po
    /// krajach" pozwala wygrać komuś kto zwiedził dużo różnych miejsc nawet
    /// z mniejszym całościowym Explorer Score). UWAGA — jednorazowa, ręczna
    /// czynność usera w CloudKit Dashboard (icloud.developer.apple.com):
    /// pole `score` jest już oznaczone Queryable+Sortable od 02.08.2026,
    /// ale `countries` NIE JEST — trzeba to dorobić RĘCZNIE zanim `sortBy:
    /// .countries` zadziała (inaczej błąd "Field 'countries' is not marked
    /// queryable/sortable"), tym samym sposobem co przy `score`. CloudKit
    /// auto-tworzy typ rekordu i pola przy pierwszym zapisie, ale NIE
    /// auto-tworzy indeksów potrzebnych do sortowania/filtrowania.
    static func topEntries(sortBy: LeaderboardSort = .score, limit: Int = 50) async throws -> [LeaderboardEntry] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: sortBy.recordKey, ascending: false)]
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: limit)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return LeaderboardEntry(record: record)
        }
    }

    /// Wpisy TYLKO dla podanych userID (28.08.2026, ranking znajomych —
    /// `FriendCircleService`) — pobrane wprost po ID rekordu (recordName ==
    /// identyfikator Sign in with Apple, patrz `submitCurrentScore`), NIE
    /// przez `CKQuery`. Nie wymaga żadnego dodatkowego indeksu w CloudKit
    /// Dashboard (w przeciwieństwie do `topEntries`), stąd sortowanie
    /// lokalne zamiast `NSSortDescriptor`. Członek kręgu, który jeszcze
    /// nigdy nie przesłał wyniku, po prostu nie ma tu rekordu — pomijany,
    /// nie traktowany jako błąd.
    static func entries(forUserIDs userIDs: [String], sortBy: LeaderboardSort) async throws -> [LeaderboardEntry] {
        guard !userIDs.isEmpty else { return [] }
        let ids = userIDs.map { CKRecord.ID(recordName: $0) }
        let results = try await publicDB.records(for: ids)
        let entries = results.values.compactMap { result -> LeaderboardEntry? in
            guard case .success(let record) = result else { return nil }
            return LeaderboardEntry(record: record)
        }
        switch sortBy {
        case .score: return entries.sorted { $0.score > $1.score }
        case .countries: return entries.sorted { $0.countries > $1.countries }
        }
    }
}

enum LeaderboardSort: String, CaseIterable, Identifiable {
    case score
    case countries

    var id: String { rawValue }
    var recordKey: String {
        switch self {
        case .score: return "score"
        case .countries: return "countries"
        }
    }
    var label: String {
        switch self {
        case .score: return L("Points")
        case .countries: return L("Countries")
        }
    }
}

struct LeaderboardEntry: Identifiable {
    let id: String
    let displayName: String
    let score: Double
    let km: Double
    let countries: Int
    let cities: Int
    let elevationM: Double
    /// `.none` dla wpisów sprzed tej zmiany (pole jeszcze nie istniało) i
    /// dla nierozpoznanych/sezonowych wartości — patrz komentarz przy
    /// `LeaderboardService.submitCurrentScore`.
    let avatarFrame: AvatarFrame

    init?(record: CKRecord) {
        guard let displayName = record["displayName"] as? String,
              let score = record["score"] as? Double else { return nil }
        id = record.recordID.recordName
        self.displayName = displayName
        self.score = score
        km = record["km"] as? Double ?? 0
        countries = record["countries"] as? Int ?? 0
        cities = record["cities"] as? Int ?? 0
        elevationM = record["elevationM"] as? Double ?? 0
        avatarFrame = AvatarFrame(rawValue: record["avatarFrame"] as? String ?? "") ?? .none
    }
}
