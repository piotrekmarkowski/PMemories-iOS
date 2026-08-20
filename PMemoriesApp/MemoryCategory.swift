import Foundation

/// Kategorie/tagi Memory poza podróżami (TODO.md 09.08.2026 — feedback
/// zewnętrzny: appka pozycjonuje się głównie wokół podróży, brak sposobu
/// organizowania Memories z życia codziennego). Opcjonalne (`nil` = brak
/// kategorii, zachowanie sprzed tej funkcji) — appka NIE zgaduje kategorii
/// automatycznie (żadnych sygnałów do tego), user wybiera ręcznie w Library.
enum MemoryCategory: String, CaseIterable, Identifiable, Codable {
    case family, weekend, birthday, roadTrip, adventure, lifeMoments

    var id: String { rawValue }

    var label: String {
        switch self {
        case .family: return L("Family")
        case .weekend: return L("Weekend")
        case .birthday: return L("Birthday")
        case .roadTrip: return L("Road Trip")
        case .adventure: return L("Adventure")
        case .lifeMoments: return L("Life Moments")
        }
    }

    var icon: String {
        switch self {
        case .family: return "person.3.fill"
        case .weekend: return "sun.max.fill"
        case .birthday: return "birthday.cake.fill"
        case .roadTrip: return "car.fill"
        case .adventure: return "mountain.2.fill"
        case .lifeMoments: return "heart.fill"
        }
    }
}
