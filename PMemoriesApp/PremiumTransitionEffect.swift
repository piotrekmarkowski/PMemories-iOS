import CoreImage
import AVFoundation

/// Efekty premium przejść (30.08.2026) — działają na piksele klatki, nie
/// tylko transform/opacity jak podstawowe 10 stylów (patrz `TransitionStyle`).
/// Każdy efekt bierze `envelope` 0...1 (0 na brzegach okna przejścia, szczyt
/// 1 dokładnie w połowie — liczone przez `PremiumTransitionGrader` jako
/// "okno Hanna", `0.5 - 0.5*cos(2π·postęp)`, żeby zaczynały/kończyły się
/// płynnie, nie skokiem) i zwraca zmodyfikowany obraz.
enum PremiumTransitionEffect: String, Codable {
    case flash
    case blurDissolve
    case lightLeak
    case glitch

    func apply(to image: CIImage, envelope: Double, canvasSize: CGSize) -> CIImage {
        guard envelope > 0.001 else { return image }
        switch self {
        case .flash: return applyFlash(to: image, envelope: envelope)
        case .blurDissolve: return applyBlurDissolve(to: image, envelope: envelope)
        case .lightLeak: return applyLightLeak(to: image, envelope: envelope, canvasSize: canvasSize)
        case .glitch: return applyGlitch(to: image, envelope: envelope)
        }
    }

    /// Rozjaśnienie do bieli w szczycie okna — dokładana biała warstwa z
    /// alpha = envelope, prościej i stabilniej na skrajnych wartościach niż
    /// tryb mieszania "screen".
    private func applyFlash(to image: CIImage, envelope: Double) -> CIImage {
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(envelope)))
            .cropped(to: image.extent)
        return white.composited(over: image)
    }

    /// Promień rozmycia rampowany z envelope — pikowe rozmycie w połowie
    /// okna, zero (ostry obraz) na brzegach, żeby łączyło się bez szwu z
    /// sąsiednimi, nierozmytymi klatkami solo.
    private func applyBlurDissolve(to image: CIImage, envelope: Double) -> CIImage {
        let radius = envelope * 18
        guard radius > 0.1 else { return image }
        return image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: image.extent)
    }

    /// Ciepła, przesuwająca się poświata z rogu kadru — proceduralny gradient
    /// (`CIRadialGradient`), bez żadnego zasobu graficznego. Środek przesuwa
    /// się wraz z `envelope`, żeby wyglądało jak przemiatające światło, nie
    /// statyczna plama w jednym miejscu.
    private func applyLightLeak(to image: CIImage, envelope: Double, canvasSize: CGSize) -> CIImage {
        let center = CGPoint(x: canvasSize.width * (0.15 + 0.7 * envelope), y: canvasSize.height * 0.15)
        let radius = max(canvasSize.width, canvasSize.height) * 0.55
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: center.x, y: center.y),
            "inputRadius0": 0,
            "inputRadius1": radius,
            "inputColor0": CIColor(red: 1, green: 0.85, blue: 0.6, alpha: CGFloat(envelope * 0.75)),
            "inputColor1": CIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0)
        ])?.outputImage?.cropped(to: image.extent) else { return image }
        return gradient.composited(over: image)
    }

    /// Rozjazd kanałów R/G/B w poziomie — każdy kanał wyizolowany osobno
    /// (`CIColorMatrix`, dwa pozostałe wyzerowane) i przesunięty w
    /// przeciwną stronę, złożone z powrotem addytywnie (`CIAdditionCompositing`,
    /// bezpieczne bo w danym pikselu tylko JEDEN z trzech obrazów niesie
    /// niezerową wartość na danym kanale). Amplituda PULSUJE (sinus) zamiast
    /// płynnie rosnąć, żeby wyglądało jak cyfrowe migotanie, nie gładkie
    /// rozmycie.
    private func applyGlitch(to image: CIImage, envelope: Double) -> CIImage {
        let pulse = (sin(envelope * .pi * 6) + 1) / 2
        let offset = CGFloat(envelope * pulse) * 14
        guard offset > 0.3 else { return image }

        func isolateChannel(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }

        let extended = image.clampedToExtent()
        let red = isolateChannel(extended, r: 1, g: 0, b: 0)
            .transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let green = isolateChannel(extended, r: 0, g: 1, b: 0)
        let blue = isolateChannel(extended, r: 0, g: 0, b: 1)
            .transformed(by: CGAffineTransform(translationX: -offset, y: 0))

        let combined = red
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
        return combined.cropped(to: image.extent)
    }
}

/// Jedno okno czasowe premium efektu w finalnym filmiku — zbierane w
/// `VideoComposer.buildInstructions` (znane tam dokładne zakresy przejść) i
/// zużywane przez `PremiumTransitionGrader` w osobnym, opcjonalnym drugim
/// przebiegu eksportu.
struct PremiumTransitionWindow {
    let range: CMTimeRange
    let effect: PremiumTransitionEffect
}
