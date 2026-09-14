import CloudKit

/// Ranking wśród znajomych (28.08.2026) — user: "ranking globalny i ranking
/// znajomych do którego będą zaproszeni ludzie". Zamiast `CKShare`
/// (cięższy natywny mechanizm współdzielenia, patrz gotcha przy Shared Trip
/// — brak publicznego API CKShare w SwiftData) — prosty kod zaproszenia +
/// dwa nowe typy rekordów w TEJ SAMEJ publicznej bazie co `LeaderboardEntry`
/// (`LeaderboardService.swift`). Globalny ranking zostaje kompletnie bez
/// zmian — to tylko warstwa FILTRUJĄCA nad tymi samymi wynikami: znajdź mój
/// krąg → userID-y członków → dociągnij ich istniejące już `LeaderboardEntry`
/// (`LeaderboardService.entries(forUserIDs:sortBy:)`).
///
/// UWAGA — jednorazowa, ręczna czynność w CloudKit Dashboard
/// (icloud.developer.apple.com), tym samym sposobem co przy `score`/
/// `countries` w `LeaderboardService`: pola `userID` i `circleID` na
/// `FriendCircleMembership` oraz `inviteCode` na `FriendCircle` muszą być
/// oznaczone Queryable, inaczej `CKQuery` niżej rzuci "Field '...' is not
/// marked queryable". CloudKit auto-tworzy typ rekordu i pola przy
/// pierwszym zapisie, ale NIE auto-tworzy indeksów do filtrowania.
enum FriendCircleService {
    private static let container = CKContainer(identifier: "iCloud.com.piotrmarkowski.pmemories")
    private static var publicDB: CKDatabase { container.publicCloudDatabase }
    private static let circleRecordType = "FriendCircle"
    private static let membershipRecordType = "FriendCircleMembership"

    enum ServiceError: Error, LocalizedError {
        case notSignedIn
        case circleNotFound

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return L("Sign in with Apple failed. Please try again.")
            case .circleNotFound: return L("Circle not found. Check the code and try again.")
            }
        }
    }

    /// Bez znaków łatwych do pomylenia przy ręcznym przepisywaniu/dyktowaniu
    /// (0/O, 1/I/L).
    private static func generateInviteCode() -> String {
        let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// Krąg, do którego należy aktualny user — `nil` jeśli jeszcze do
    /// żadnego nie dołączył.
    static func myCircle() async throws -> FriendCircle? {
        guard let userIdentifier = await AuthManager.shared.userIdentifier else {
            throw ServiceError.notSignedIn
        }
        let predicate = NSPredicate(format: "userID == %@", userIdentifier)
        let query = CKQuery(recordType: membershipRecordType, predicate: predicate)
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
        guard let (_, result) = results.first, case .success(let membershipRecord) = result,
              let circleID = membershipRecord["circleID"] as? String else { return nil }
        let circleRecord = try await publicDB.record(for: CKRecord.ID(recordName: circleID))
        return FriendCircle(record: circleRecord)
    }

    /// Zakłada nowy krąg (owner = aktualny user) i od razu dopisuje jego
    /// samego jako pierwszego członka.
    static func createCircle() async throws -> FriendCircle {
        guard let userIdentifier = await AuthManager.shared.userIdentifier,
              let displayName = await AuthManager.shared.displayName else {
            throw ServiceError.notSignedIn
        }
        let circleRecord = CKRecord(recordType: circleRecordType)
        circleRecord["ownerID"] = userIdentifier as CKRecordValue
        circleRecord["inviteCode"] = generateInviteCode() as CKRecordValue
        circleRecord["createdAt"] = Date() as CKRecordValue
        let saved = try await publicDB.save(circleRecord)
        try await upsertMembership(circleID: saved.recordID.recordName, userID: userIdentifier, displayName: displayName)
        guard let circle = FriendCircle(record: saved) else { throw ServiceError.circleNotFound }
        return circle
    }

    /// Dołącza do kręgu po kodzie zaproszenia. Jeden krąg naraz (MVP) —
    /// jeśli user był już w INNYM kręgu, jego stare członkostwo jest
    /// usuwane zanim dopisze się nowe.
    static func joinCircle(code: String) async throws -> FriendCircle {
        guard let userIdentifier = await AuthManager.shared.userIdentifier,
              let displayName = await AuthManager.shared.displayName else {
            throw ServiceError.notSignedIn
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let predicate = NSPredicate(format: "inviteCode == %@", trimmedCode)
        let query = CKQuery(recordType: circleRecordType, predicate: predicate)
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
        guard let (_, result) = results.first, case .success(let circleRecord) = result else {
            throw ServiceError.circleNotFound
        }
        if let existing = try? await myCircle(), existing.id != circleRecord.recordID.recordName {
            try? await publicDB.deleteRecord(withID: membershipRecordID(circleID: existing.id, userID: userIdentifier))
        }
        try await upsertMembership(circleID: circleRecord.recordID.recordName, userID: userIdentifier, displayName: displayName)
        guard let circle = FriendCircle(record: circleRecord) else { throw ServiceError.circleNotFound }
        return circle
    }

    static func leaveCurrentCircle() async throws {
        guard let userIdentifier = await AuthManager.shared.userIdentifier else {
            throw ServiceError.notSignedIn
        }
        guard let circle = try await myCircle() else { return }
        try await publicDB.deleteRecord(withID: membershipRecordID(circleID: circle.id, userID: userIdentifier))
    }

    /// UserID-y wszystkich członków danego kręgu (włącznie z aktualnym
    /// userem).
    static func memberIDs(circleID: String) async throws -> [String] {
        let predicate = NSPredicate(format: "circleID == %@", circleID)
        let query = CKQuery(recordType: membershipRecordType, predicate: predicate)
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return record["userID"] as? String
        }
    }

    /// Recordname deterministyczny (krąg+user) — naturalny upsert, jeden
    /// user nie może dwa razy dołączyć do tego samego kręgu.
    private static func membershipRecordID(circleID: String, userID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(circleID)_\(userID)")
    }

    private static func upsertMembership(circleID: String, userID: String, displayName: String) async throws {
        let recordID = membershipRecordID(circleID: circleID, userID: userID)
        let record: CKRecord
        if let existing = try? await publicDB.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: membershipRecordType, recordID: recordID)
        }
        record["circleID"] = circleID as CKRecordValue
        record["userID"] = userID as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record["joinedAt"] = Date() as CKRecordValue
        _ = try await publicDB.save(record)
    }
}

struct FriendCircle: Identifiable, Equatable {
    let id: String
    let ownerID: String
    let inviteCode: String

    init?(record: CKRecord) {
        guard let ownerID = record["ownerID"] as? String,
              let inviteCode = record["inviteCode"] as? String else { return nil }
        id = record.recordID.recordName
        self.ownerID = ownerID
        self.inviteCode = inviteCode
    }
}
