import Foundation

/// Publiczny profil odkrywcy — link do udostępnienia z podsumowaniem
/// statystyk (13.08.2026, user: "wprowadźmy lokalnie... publiczny profil").
/// Ten sam wzorzec co `PlannedTripTransfer.swift`/`ShareLinkService` —
/// JEDNORAZOWY snapshot wysyłany na VPS, nie żywe połączenie (appka nie ma
/// mechanizmu współdzielenia na żywo, patrz Shared Trip/CKShare COFNIĘTE
/// 12/13.08.2026) — user chce zregenerować link ręcznie (ten sam przycisk),
/// nie automatyczną synchronizację.
struct ExplorerProfilePassportEntry: Codable {
    var countryCode: String
    var countryName: String
    var firstVisitDate: Date?
}

struct ExplorerProfileDTO: Codable {
    var displayName: String
    var explorerScoreTotal: Double
    var explorerScoreTier: String
    var countries: Int
    var cities: Int
    var totalKm: Double
    var tripsCount: Int
    var passport: [ExplorerProfilePassportEntry]
}

enum ExplorerProfileService {
    // Osobna domena dedykowana PMemories (13.08.2026) zamiast osobistej
    // domeny portfolio — ta sama ścieżka `/pmemories/` po stronie backendu
    // (VPS), zero zmian w `pmemories_share_server.py`.
    private static let baseURL = URL(string: "https://pmemories.duckdns.org/pmemories")!

    enum ServiceError: Error {
        case invalidResponse
    }

    static func createProfileLink(for dto: ExplorerProfileDTO) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/profiles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(dto)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.invalidResponse
        }
        struct CreateResponse: Decodable { let id: String }
        let decoded = try JSONDecoder().decode(CreateResponse.self, from: data)
        return baseURL.appendingPathComponent("profile/\(decoded.id)")
    }
}
