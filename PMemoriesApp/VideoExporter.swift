import AVFoundation
import Photos

/// Eksportuje gotową kompozycję do pliku i zapisuje do biblioteki zdjęć.
///
/// Rozdzielone na `export`/`saveToPhotos` (09.08.2026, dodanie filtrów
/// kolorystycznych — `ColorGrader`) — `EditView.performExport()` wstawia
/// opcjonalny drugi przebieg (`ColorGrader.apply`) MIĘDZY tymi dwoma
/// krokami, gdy user wybrał filtr w Style. Bez filtra (domyślnie) appka
/// robi dokładnie to co wcześniej: jeden przebieg, zero dodatkowego kosztu.
enum VideoExporter {
    enum ExportError: Error {
        case sessionCreationFailed
    }

    /// Renderuje kompozycję do pliku tymczasowego — CALLER odpowiada za
    /// posprzątanie zwróconego URL (patrz `TempFileCleanup`/`EditView.
    /// performExport`), bo w międzyczasie może przejść jeszcze przez
    /// `ColorGrader`.
    static func export(
        composedProject: VideoComposer.ComposedProject, onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard let exportSession = AVAssetExportSession(
            asset: composedProject.composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.sessionCreationFailed
        }
        // Bez tego Rotate/Crop z Trim-arkusza nie miałyby żadnego efektu —
        // sama kompozycja niesie tylko czas/kolejność klipów, transformy
        // (obrót/skala/kadrowanie) żyją w osobnej `AVVideoComposition`.
        exportSession.videoComposition = composedProject.videoComposition
        exportSession.audioMix = composedProject.audioMix

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // `AVAssetExportSession` nie ma callbacku postępu — jedyny sposób to
        // odpytywanie `.progress` (Float 0...1) w tle, równolegle z samym
        // eksportem. Zadanie odpytujące anulowane od razu po zakończeniu
        // eksportu (defer), żeby nie zostawić wiszącej pętli.
        let progressTask = Task {
            while !Task.isCancelled {
                onProgress?(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { progressTask.cancel() }

        try await exportSession.export(to: outputURL, as: .mov)
        onProgress?(1.0)
        return outputURL
    }

    /// Zwraca `PHAsset.localIdentifier` nowo utworzonego wideo — Library
    /// zapamiętuje go na projekcie (`SavedProject.exportedAssetIdentifier`),
    /// żeby dało się odtworzyć gotowy filmik wprost z appki, bez szukania
    /// go w bibliotece Zdjęć. NIE kasuje `fileURL` — caller decyduje kiedy
    /// (patrz `export` wyżej).
    @discardableResult
    static func saveToPhotos(fileURL: URL) async throws -> String? {
        var createdAssetIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            createdAssetIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
        }
        return createdAssetIdentifier
    }
}
