import Foundation

/// Siatka bezpieczeństwa na zaśmiecanie `FileManager.default.temporaryDirectory`
/// (04.08.2026, user: "apka ma być lekka dla telefonu i nie ma go zaśmiecać").
///
/// Znalezione realnie na telefonie: 253 plików `.mov`, 11GB, część sprzed
/// dwóch miesięcy — eksport (`VideoExporter`, `ImageToVideoRenderer`),
/// otwieranie projektu do edycji (`MediaAssetLoader.loadMediaItems` kopiuje
/// PEŁNE wideo z Photos przy KAŻDYM otwarciu edytora) i Live Photo
/// (`LivePhotoVideoExtractor`) piszą do katalogu tymczasowego, ale nigdy go
/// same nie sprzątają — `AVMutableComposition` czyta te pliki LENIWIE
/// (dopiero przy eksporcie/podglądzie), więc nie da się ich bezpiecznie
/// skasować zaraz po utworzeniu bez ryzyka zepsucia aktywnej sesji edycji.
/// Zamiast oplatać cały, już dziś skomplikowany i wielokrotnie łatany
/// pipeline edycji ręcznym śledzeniem cyklu życia każdego pliku, czyścimy
/// przy starcie appki wszystko starsze niż próg, po którym ŻADNA legalna
/// operacja (eksport max ~15 min, edycja w jednej sesji) nie mogłaby już
/// tego pliku potrzebować.
enum TempFileCleanup {
    static func purgeStaleTemporaryFiles(olderThan maxAge: TimeInterval = 3600) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in contents {
            guard let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modDate < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
