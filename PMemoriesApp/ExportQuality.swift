import CoreGraphics

/// Poziom jakości/rozdzielczości eksportu — appka robi wideo w formacie
/// pionowym (9:16, jak Reels/TikTok), więc to skalowanie TEGO wymiaru, nie
/// zmiana proporcji obrazu.
enum ExportQuality: String, CaseIterable, Identifiable {
    case sd720, hd1080, uhd4k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sd720: return "720p"
        case .hd1080: return "1080p (HD)"
        case .uhd4k: return "4K (Ultra HD)"
        }
    }

    var canvasSize: CGSize {
        switch self {
        case .sd720: return CGSize(width: 720, height: 1280)
        case .hd1080: return CGSize(width: 1080, height: 1920)
        case .uhd4k: return CGSize(width: 2160, height: 3840)
        }
    }
}
