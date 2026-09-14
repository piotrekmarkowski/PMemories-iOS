import AVFoundation
import CoreImage

/// Trzeci, OPCJONALNY przebieg eksportu (30.08.2026) — nakłada efekty
/// premium przejść (`PremiumTransitionEffect`) TYLKO w oknach czasowych,
/// gdzie user faktycznie wybrał jeden z tych stylów. Ten sam wzorzec co
/// `ColorGrader` (drugi pełny przebieg na już wyrenderowanym pliku,
/// `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`) —
/// świadomie OSOBNY plik/przebieg, nie połączony z `ColorGrader`: jeden
/// nakłada efekt na CAŁYM filmie, ten TYLKO w krótkich oknach przejść, więc
/// dzielenie ich w jednym handlerze wymagałoby przekazywania dwóch
/// niezależnych zestawów parametrów przez tę samą funkcję.
enum PremiumTransitionGrader {
    enum GraderError: Error {
        case sessionCreationFailed
    }

    static func apply(
        _ windows: [PremiumTransitionWindow], canvasSize: CGSize, to inputURL: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            guard let window = windows.first(where: { $0.range.containsTime(request.compositionTime) }),
                  window.range.duration.seconds > 0 else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            let progress = (request.compositionTime - window.range.start).seconds / window.range.duration.seconds
            // "Okno Hanna" — 0 na brzegach okna, szczyt 1 dokładnie w
            // połowie, płynne wejście/wyjście zamiast skoku.
            let envelope = 0.5 - 0.5 * cos(2 * Double.pi * min(max(progress, 0), 1))
            let output = window.effect.apply(to: request.sourceImage, envelope: envelope, canvasSize: canvasSize)
            request.finish(with: output, context: nil)
        })

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw GraderError.sessionCreationFailed
        }
        exportSession.videoComposition = composition

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

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
}
