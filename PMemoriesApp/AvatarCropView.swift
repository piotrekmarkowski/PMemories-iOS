import SwiftUI
import UIKit

/// Kadrowanie awatara (TODO.md 08.08.2026 — feedback z testów: "appka
/// bierze zdjęcie 1:1 bez pozwolenia userowi wybrać które miejsce zdjęcia
/// wyląduje w okrągłej ramce"). Przeciąganie + szczypanie w kole, potem
/// realny crop w PIKSELACH oryginalnego zdjęcia — NIE zrzut ekranu
/// podglądu (`feedback_crop_at_target_scale` — małe błędy pozycji na
/// zmniejszonym podglądzie stają się ogromne po powiększeniu na realnym
/// zdjęciu, ta sama pułapka co przy ikonce appki).
struct AvatarCropView: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    /// Rozmiar wyświetlanego koła w punktach — stała używana w matematyce
    /// crop, więc musi być TĄ SAMĄ wartością co `.frame` niżej.
    private let displaySize: CGFloat = 280
    private let minAdditionalScale: CGFloat = 1.0
    private let maxAdditionalScale: CGFloat = 4.0

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var additionalScale: CGFloat = 1.0
    @State private var lastAdditionalScale: CGFloat = 1.0

    /// Współczynnik `scaledToFill` przy `additionalScale == 1` — najmniejsze
    /// powiększenie które w pełni pokrywa okrągłą ramkę bez pustych brzegów.
    private var baseScale: CGFloat {
        max(displaySize / image.size.width, displaySize / image.size.height)
    }

    private var totalScale: CGFloat { baseScale * additionalScale }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: image.size.width * totalScale, height: image.size.height * totalScale)
                    .offset(offset)
                    .frame(width: displaySize, height: displaySize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .contentShape(Circle())
                    .gesture(dragGesture)
                    .simultaneousGesture(magnificationGesture)
                Text("Drag to reposition, pinch to zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(croppedImage()) }
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                ))
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                additionalScale = min(max(lastAdditionalScale * value, minAdditionalScale), maxAdditionalScale)
                offset = clampedOffset(offset)
            }
            .onEnded { _ in
                lastAdditionalScale = additionalScale
                lastOffset = offset
            }
    }

    /// Nie pozwala odsłonić pustego tła poza krawędzią zdjęcia — maksymalny
    /// offset w każdej osi to połowa nadwyżki wyświetlanego zdjęcia nad
    /// rozmiarem okrągłej ramki, przy AKTUALNYM `totalScale`.
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let displayedWidth = image.size.width * totalScale
        let displayedHeight = image.size.height * totalScale
        let maxX = max(0, (displayedWidth - displaySize) / 2)
        let maxY = max(0, (displayedHeight - displaySize) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    /// Realny crop w pikselach ORYGINALNEGO zdjęcia — odwraca dokładnie tę
    /// samą geometrię co widok wyżej (środek widocznego koła w
    /// współrzędnych obrazu, rozmiar wycinka = `displaySize / totalScale`),
    /// zamiast renderować to co widać na ekranie.
    private func croppedImage() -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let pixelsPerPoint = CGFloat(cgImage.width) / image.size.width

        let centerX = image.size.width / 2 - offset.width / totalScale
        let centerY = image.size.height / 2 - offset.height / totalScale
        let cropSizePoints = displaySize / totalScale

        var cropRect = CGRect(
            x: (centerX - cropSizePoints / 2) * pixelsPerPoint,
            y: (centerY - cropSizePoints / 2) * pixelsPerPoint,
            width: cropSizePoints * pixelsPerPoint,
            height: cropSizePoints * pixelsPerPoint
        )
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        cropRect = cropRect.intersection(bounds)
        guard !cropRect.isEmpty, let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
