import CoreImage

/// Filtr kolorystyczny nakładany na CAŁY finalny filmik — 09.08.2026, user:
/// "coś w stylu retro i kamer z '54". Osobna, DRUGA klasa efektów obok
/// `TransitionStyle` (per-przejście) — ten działa na każdej klatce całego
/// filmu. `.none` (domyślne) = appka eksportuje dokładnie tak jak wcześniej,
/// zero dodatkowego przebiegu (patrz `ColorGrader`/`VideoExporter`).
enum ColorStyle: String, CaseIterable, Identifiable, Codable {
    case none
    case vintage
    // Rozbudowane 09.08.2026 — infrastruktura (drugi przebieg, `ColorGrader`)
    // już stoi po `.vintage`, więc kolejne style to tylko nowe kombinacje
    // `CIFilter`, zero dodatkowej pracy nad pipeline'em.
    case blackAndWhite
    case vibrant
    case cinematic
    case warm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L("None")
        case .vintage: return L("Vintage")
        case .blackAndWhite: return L("Black & White")
        case .vibrant: return L("Vibrant")
        case .cinematic: return L("Cinematic")
        case .warm: return L("Warm")
        }
    }

    /// Łańcuch `CIFilter` dla tego stylu — czyste funkcje na `CIImage`,
    /// używane przez `ColorGrader` (drugi przebieg eksportu, `AVMutableVideo
    /// Composition(asset:applyingCIFiltersWithHandler:)`). Świadomie BEZ
    /// ziarna filmowego (grain) na start — sepia+winieta+desaturacja już daje
    /// wyraźny "retro" efekt, ziarno to osobny, bardziej złożony dodatek do
    /// rozważenia później, jeśli user go zechce.
    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .vintage:
            var output = image
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.75,
                kCIInputContrastKey: 1.08,
                kCIInputBrightnessKey: 0.02
            ])
            output = output.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.3])
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 1.1,
                kCIInputRadiusKey: 1.6
            ])
            return output
        case .blackAndWhite:
            var output = image
            output = output.applyingFilter("CIPhotoEffectNoir")
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.05])
            return output
        case .vibrant:
            var output = image
            output = output.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.6])
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.15,
                kCIInputContrastKey: 1.08
            ])
            return output
        case .cinematic:
            // Chłodniejsza tonacja + lekka winieta + wyższy kontrast —
            // przybliżenie popularnego "teal & orange" bez pełnego split
            // toningu (za dużo dla prostego łańcucha filtrów).
            var output = image
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.9,
                kCIInputContrastKey: 1.12
            ])
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7500, y: 0)
            ])
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 0.8,
                kCIInputRadiusKey: 1.8
            ])
            return output
        case .warm:
            var output = image
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5000, y: 0)
            ])
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.08])
            return output
        }
    }
}
