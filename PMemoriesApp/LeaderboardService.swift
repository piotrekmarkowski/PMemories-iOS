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

    /// Zapisuje/aktualizuje wynik AKTUALNEGO usera (upsert po stałym ID) —
    /// wołane po każdym przeliczeniu `ExplorerScore` (patrz `AchievementsView`),
    /// nie na jakimś osobnym timerze — zawsze najświeższy stan.
    static func submitCurrentScore(score: ExplorerScore, km: Double, countries: Int, cities: Int, elevationM: Double) async throws {
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
    }
}
