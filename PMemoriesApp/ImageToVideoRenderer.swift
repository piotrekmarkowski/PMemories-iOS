import AVFoundation
import UIKit
import CoreImage

/// Renderuje statyczne zdjęcie do krótkiego pliku wideo o zadanym czasie
/// trwania, żeby móc je traktować jak każdy inny klip w kompozycji.
enum ImageToVideoRenderer {
    enum RenderError: Error {
        case pixelBufferCreationFailed
        case writerFailed(String)
    }

    static func render(
        image: UIImage,
        duration: Double,
        size: CGSize = CGSize(width: 1080, height: 1920),
        fps: Int32 = 30
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // 23.08.2026 — ProRes422HQ (wprowadzone 29.07.2026 dla jakości,
        // patrz historia w HISTORIA.md) ZDJĘTE po realnym, powtarzalnym
        // buga zgłoszonym przez testerkę: `AVFoundationErrorDomain -11838`
        // ("The operation is not supported for this media") z podkodem
        // `NSOSStatusErrorDomain -16976`, ZAWSZE w fazie `mainExport`
        // (potwierdzone przez etykietowanie faz z build 19), niezależnie od
        // filtra/jakości, 100% powtarzalne na JEJ URZĄDZENIU z tymi samymi
        // zdjęciami. Wsparcie dekodowania ProRes w potoku
        // `AVAssetExportSession` nie jest jednolite na wszystkich modelach
        // iPhone'a — appka trafia do userów przez TestFlight na dowolny
        // sprzęt, nie tylko na urządzenia developera, gdzie to zawsze
        // działało. HEVC zamiast ProRes: praktycznie zero realnej straty
        // jakości TU konkretnie, bo ten plik pośredni to i tak JEDNA,
        // NIERUCHOMA klatka powtórzona przez całą długość klipu (ruch typu
        // Ken Burns dokłada się PÓŹNIEJ, w `VideoComposer`, przez transformy
        // na poziomie kompozycji, nie tutaj) — HEVC kompresuje statyczną
        // treść niemal bezstratnie nawet przy umiarkowanym bitrate, a jest
        // dekodowalny univerzalnie na każdym urządzeniu z iOS 18+.
        let pixelCount = Int(size.width * size.height)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: pixelCount * 8,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        // 23.08.2026 — w logach urządzenia testerki KAŻDE wywołanie tego
        // renderera zostawiało "PERFORMANCE WARNING: Appending non-IOSurface
        // backed CVPixelBuffer" — bufor tworzony zwykłym `CVPixelBufferCreate`
        // (niżej, `makePixelBuffer`) nie ma wsparcia IOSurface, więc encoder
        // musi robić powolną kopię po stronie CPU zamiast szybkiej ścieżki
        // GPU. Prawdziwe wideo z kamery ZAWSZE ma bufory IOSurface — to jest
        // unikalne dla zdjęć renderowanych na wideo tym mechanizmem, dokładnie
        // pasujące do tego że bug reprodukuje się WYŁĄCZNIE na projektach z
        // samych zdjęć. `kCVPixelBufferIOSurfacePropertiesKey` (pusty słownik
        // wystarcza, żeby wymusić alokację z poparciem IOSurface) w OBU
        // miejscach (tu i w `makePixelBuffer` niżej, bo to tam faktycznie
        // powstaje bufor przekazywany do adaptora).
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBuffer = makePixelBuffer(from: image, size: size) else {
            throw RenderError.pixelBufferCreationFailed
        }

        let frameCount = max(1, Int(duration * Double(fps)))
        var frameIndex = 0
        while frameIndex < frameCount {
            // Bug znaleziony 03.08.2026 (przegląd kodu) — pętla sprawdzała
            // WYŁĄCZNIE `isReadyForMoreMediaData`, bez sprawdzenia czy
            // `writer` w międzyczasie nie padł (pełny dysk, brak uprawnień).
            // Po realnym błędzie `isReadyForMoreMediaData` NIGDY nie wraca
            // do `true` — pętla kręciła się w nieskończoność zamiast
            // przerwać się i rzucić `writerFailed` (ten sam błąd, który już
            // istniał NIŻEJ, ale był nieosiągalny w tym scenariuszu, bo
            // pętla nigdy nie dochodziła do tego miejsca).
            if writer.status == .failed {
                throw RenderError.writerFailed(writer.error?.localizedDescription ?? "unknown write error")
            }
            if input.isReadyForMoreMediaData {
                let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                adaptor.append(pixelBuffer, withPresentationTime: time)
                frameIndex += 1
            } else {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "unknown write error")
        }

        return outputURL
    }

    private static func makePixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        guard let cgImage = normalizedCGImage(from: image), let context else { return nil }

        // `CVPixelBufferCreate` NIE gwarantuje wyzerowanej pamięci — bez tego
        // wypełnienia, jeśli `blurredFillImage` poniżej zwróci `nil` (np.
        // przy zdjęciu HDR/szerokiego gamutu, gdzie CIContext bywa
        // kapryśny), w pustych pasach zostawały resztki bufora po
        // WCZEŚNIEJ renderowanym zdjęciu z tego samego eksportu — user
        // zobaczył fragment zupełnie innego zdjęcia (sufit, blat stołu)
        // rozmazany nad i pod właściwym zdjęciem. Jawne czarne tło jako
        // baza gwarantuje, że najgorszy przypadek to zwykły czarny pas, nie
        // cudza treść.
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // ŻADNEGO przycinania — niezależnie jak dobre byłoby wykrywanie
        // twarzy/sylwetek, przy bardzo szerokim zdjęciu z ludźmi rozstawionymi
        // na całej szerokości i tak coś by ucięło (user: "obcinanie zdjęć to
        // nie jest coś dobrego"). Zamiast zgadywać co wyciąć: całe zdjęcie
        // zawsze w kadrze (aspect-FIT), a puste pasy wypełnia rozmyte,
        // powiększone tło z tego samego zdjęcia zamiast czarnych belek —
        // ten sam wzorzec co Instagram Stories.
        if let background = blurredFillImage(from: cgImage, size: size) {
            context.draw(background, in: CGRect(origin: .zero, size: size))
        }

        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let frameAspect = size.width / size.height
        let fitRect: CGRect
        if imageAspect > frameAspect {
            let fitHeight = size.width / imageAspect
            fitRect = CGRect(x: 0, y: (size.height - fitHeight) / 2, width: size.width, height: fitHeight)
        } else {
            let fitWidth = size.height * imageAspect
            fitRect = CGRect(x: (size.width - fitWidth) / 2, y: 0, width: fitWidth, height: size.height)
        }
        context.draw(cgImage, in: fitRect)

        return buffer
    }

    /// Rozmyte, powiększone (aspect-FILL — przycięcie tu jest OK, to tylko
    /// dekoracja w tle) tło wypełniające całą kanwę. Rozmycie liczone na
    /// mocno pomniejszonej kopii (nie potrzeba pełnej rozdzielczości do
    /// czegoś co i tak będzie rozmyte) — szybsze, artefakty pomniejszenia
    /// znikają pod rozmyciem.
    private static func blurredFillImage(from cgImage: CGImage, size: CGSize) -> CGImage? {
        let downscaled = downscaled(cgImage, maxDimension: 400)
        let ciImage = CIImage(cgImage: downscaled)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(30.0, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage else { return nil }

        let downscaledWidth = CGFloat(downscaled.width)
        let downscaledHeight = CGFloat(downscaled.height)
        let imageAspect = downscaledWidth / downscaledHeight
        let frameAspect = size.width / size.height
        let scale: CGFloat = imageAspect > frameAspect ? size.height / downscaledHeight : size.width / downscaledWidth
        let scaledImage = blurred.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaledImage.extent
        let cropRect = CGRect(
            x: extent.midX - size.width / 2,
            y: extent.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        return sharedCIContext.createCGImage(scaledImage, from: cropRect)
    }

    /// Tworzenie `CIContext` kompiluje wewnętrzny pipeline GPU/Metal —
    /// realnie kosztowne, jednorazowe wywołanie. Jeden, dzielony między
    /// wszystkimi zdjęciami w projekcie, zamiast tworzenia od nowa dla
    /// KAŻDEGO zdjęcia (tak było pierwotnie — realny, samodzielnie
    /// wprowadzony wkład w wolny eksport przy wielu zdjęciach).
    private static let sharedCIContext = CIContext()

    private static func downscaled(_ cgImage: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard max(width, height) > maxDimension else { return cgImage }
        let scale = maxDimension / max(width, height)
        let newWidth = max(1, Int(width * scale))
        let newHeight = max(1, Int(height * scale))
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? cgImage
    }

    /// `UIImage.cgImage` zwraca SUROWE piksele, całkowicie ignorując
    /// `imageOrientation` (metadane EXIF o obrocie, które ma prawie każde
    /// zdjęcie z aparatu) — stąd zdjęcia pionowe wychodziły na bok/do góry
    /// nogami. Dodatkowo `image.cgImage` bywa `nil` dla niektórych zdjęć
    /// HEIC/szerokiego gamutu, co wywalało cały eksport
    /// (`RenderError.pixelBufferCreationFailed`, "error 0"). Rysowanie przez
    /// `UIImage.draw` (wysokopoziomowe, honoruje `imageOrientation`) do
    /// świeżego `UIGraphicsImageRenderer` naprawia oba na raz — wynikowy
    /// `CGImage` ma już poprawnie "wypieczoną" orientację i zawsze istnieje.
    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalized.cgImage
    }
}
