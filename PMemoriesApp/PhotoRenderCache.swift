import Foundation

/// Cache renderów zdjęć (`ImageToVideoRenderer.render`) trwający przez cały
/// czas życia procesu appki — user re-eksportuje ten sam projekt wielokrotnie
/// podczas edycji (napis, kolejność, głośność muzyki), a bez cache'a KAŻDE
/// zdjęcie renderowało się i kodowało do ProRes od nowa przy każdym
/// eksporcie, nawet gdy jego piksele wcale się nie zmieniły. Rozważana była
/// pełna eliminacja pliku pośredniego przez własny `AVVideoCompositing`, ale
/// w AVFoundation własny compositor obsługuje WSZYSTKIE klatki filmu naraz
/// (nie da się go podłączyć tylko do zdjęć) — musiałby ręcznie odtwarzać też
/// przenikanie i PiP, dopiero co ustabilizowane. Cache renderów daje realny
/// zysk czasu przy dużo mniejszym ryzyku (30.07.2026).
actor PhotoRenderCache {
    static let shared = PhotoRenderCache()

    /// Piksele wyrenderowanego klipu zależą od tożsamości zdjęcia, jego
    /// czasu trwania (liczba klatek) i rozmiaru kanwy — zmiana
    /// KTÓREGOKOLWIEK z nich wymaga faktycznie innego renderu.
    struct Key: Hashable {
        let assetIdentifier: String
        let duration: Double
        let width: Int
        let height: Int
    }

    private var entries: [Key: URL] = [:]

    /// `fileExists` na wypadek gdyby system wyczyścił katalog `tmp/` między
    /// eksportami — bez tej weryfikacji zwrócilibyśmy URL do nieistniejącego
    /// pliku i eksport wywaliłby się dalej w łańcuchu.
    func cachedURL(for key: Key) -> URL? {
        guard let url = entries[key], FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func store(_ url: URL, for key: Key) {
        entries[key] = url
    }
}
