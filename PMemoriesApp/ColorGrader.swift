import AVFoundation
import CoreImage

/// Drugi, OPCJONALNY przebieg eksportu — nakłada `ColorStyle` na już
/// wyrenderowany plik (09.08.2026). Osobny od głównej kompozycji
/// (`VideoComposer`/`VideoExporter`) świadomie: `AVMutableVideoComposition
/// (asset:applyingCIFiltersWithHandler:)` sam generuje własne instrukcje
/// renderowania i nie da się go połączyć z istniejącymi ręcznymi
/// instrukcjami (przejścia/PiP/transformy per-klip) w jednym przebiegu —
/// próba połączenia wymagałaby prawdziwego custom `AVVideoCompositing`,
/// świadomie odrzuconego wcześniej jako "wszystko albo nic" (patrz
/// `TransitionStyle.swift`). Koszt tego kompromisu: eksport z filtrem trwa
/// dodatkowo tyle samo co bez niego (drugi pełny transcode) — ale TYLKO gdy
/// user faktycznie wybrał filtr (`ColorStyle != .none`), więc domyślny
/// przepływ (bez filtra) zostaje dokładnie tak szybki jak dotąd.
enum ColorGrader {
    enum GraderError: Error {
        case sessionCreationFailed
    }

    static func apply(_ style: ColorStyle, to inputURL: URL, onProgress: ((Double) -> Void)? = nil) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let output = style.apply(to: request.sourceImage)
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
