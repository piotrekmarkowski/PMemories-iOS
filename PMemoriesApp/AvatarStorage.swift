import UIKit

/// Zdjęcie profilowe usera — user 31.07.2026: "może w awatarze będzie
/// można wstawić też swoje zdjęcie?" (UI.md 27.07.2026: "prawdziwe zdjęcie
/// LUB inicjał zamiast SF Symbol" — inicjał zrobiony najpierw, to dokłada
/// drugą opcję). Zapisane jako plik w Application Support (nie UserDefaults
/// — binarne dane zdjęcia rozdęłyby plist), niezależnie od zdjęć w
/// bibliotece Photos (appka nie trzyma referencji do `PHAsset`, tylko
/// własną, skompresowaną kopię — ten sam duch co `MediaAssetLoader`
/// cache'ujący miniaturki lokalnie).
enum AvatarStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatar.jpg")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
