import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Wspólna logika wczytywania wybranych zdjęć/wideo w MediaItem — używana
/// zarówno przy tworzeniu nowego projektu (HomeView), jak i przy dokładaniu
/// kolejnych elementów w trakcie edycji (EditView).
enum MediaItemLoader {
    static func load(from selection: [PhotosPickerItem], onProgress: ((Double) -> Void)? = nil) async -> [MediaItem] {
        var loaded: [MediaItem] = []
        let total = selection.count
        for (index, pickerItem) in selection.enumerated() {
            let isLivePhoto = pickerItem.supportedContentTypes.contains(.livePhoto)

            var pairedVideoURL: URL?
            if isLivePhoto, let identifier = pickerItem.itemIdentifier {
                pairedVideoURL = try? await LivePhotoVideoExtractor.pairedVideoURL(
                    forAssetLocalIdentifier: identifier
                )
            }

            // `supportedContentTypes.contains(.movie)` bywa zawodne — część
            // formatów wideo z Photos (np. niektóre nagrania w wysokiej
            // rozdzielczości/slow-mo) nie zawsze zgłasza `.movie` wprost w
            // tej liście, mimo że transfer jako plik wideo się udaje. Zamiast
            // ufać samej deklaracji typu, próbujemy realnie wczytać plik jako
            // `MovieFile` — jeśli się uda, TO jest dowód że to wideo,
            // niezależnie od tego co zgłosił `supportedContentTypes`.
            var videoURL: URL?
            if !isLivePhoto {
                videoURL = try? await pickerItem.loadTransferable(type: MovieFile.self)?.url
            }
            let isVideo = videoURL != nil || pickerItem.supportedContentTypes.contains(.movie)

            // Miniaturka: dla wideo klatka wyciągnięta przez
            // `AVAssetImageGenerator` — surowe bajty pliku wideo (MOV/MP4)
            // NIE są obrazem, `UIImage(data:)` na nich zawsze zwracało `nil`,
            // stąd puste/szare kwadraty w osi czasu dla każdego klipu wideo.
            // Dla zdjęć/Live Photo wprost z danych transferowanych przez
            // picker, tak jak wcześniej.
            var thumbnail: UIImage?
            if isVideo, let videoURL {
                thumbnail = await videoThumbnail(from: videoURL)
            } else if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                thumbnail = UIImage(data: data)
            }

            // Do suwaka Trim — potrzebujemy długości całego źródłowego klipu,
            // nie tylko wybranego czasu wyświetlania.
            var sourceDuration: Double?
            if let sourceURL = videoURL ?? pairedVideoURL {
                sourceDuration = try? await AVURLAsset(url: sourceURL).load(.duration).seconds
            }

            loaded.append(
                MediaItem(
                    pickerItemId: pickerItem.itemIdentifier,
                    isLivePhoto: isLivePhoto,
                    isVideo: isVideo,
                    thumbnail: thumbnail,
                    useMotion: isLivePhoto,
                    pairedVideoURL: pairedVideoURL,
                    videoURL: videoURL,
                    duration: 3.0,
                    sourceDuration: sourceDuration
                )
            )
            onProgress?(Double(index + 1) / Double(max(1, total)))
        }
        return loaded
    }

    /// Klatka z wideo do miniaturki w osi czasu — `appliesPreferredTrackTransform`
    /// honoruje transform nagrania (ta sama kategoria buga co orientacja
    /// zdjęć w `ImageToVideoRenderer`: bez tego miniaturka klipu nagranego
    /// pionowo mogłaby wyjść na bok).
    private static func videoThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
