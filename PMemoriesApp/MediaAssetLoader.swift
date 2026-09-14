import Foundation
import Photos
import UIKit
import AVFoundation
import CoreLocation

/// Odtwarza `MediaItem` (miniaturka, plik wideo) z samego identyfikatora
/// `PHAsset` — używane przy otwieraniu zapisanego `SavedProject`, kiedy
/// oryginalny `PhotosPickerItem` (i jego tymczasowe pliki) już dawno nie
/// istnieje. Dopełnienie `LivePhotoVideoExtractor` (ten sam wzorzec
/// pobierania zasobu po identyfikatorze), tylko dla zwykłego wideo i
/// miniaturki.
enum MediaAssetLoader {
    enum LoadError: Error {
        case assetNotFound
        case videoResourceNotFound
    }

    static func videoURL(forAssetLocalIdentifier identifier: String) async throws -> URL {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { throw LoadError.assetNotFound }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .video }) else {
            throw LoadError.videoResourceNotFound
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: videoResource, toFile: destination, options: options
            ) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        // 23.08.2026 — `writeData` kończy się bez błędu, ale to NIE gwarantuje
        // że zapisany plik jest kompletnym, poprawnym wideo (np. przerwane
        // pobieranie z iCloud mogło zostawić okrojony plik). Bez tej
        // kontroli taki plik szedł prosto do kompozycji/eksportu i dawał
        // dopiero tam kryptyczny błąd AVFoundation. Sprawdzenie TERAZ daje
        // jasny, konkretny błąd we właściwym miejscu.
        try await Self.validatePlayableVideo(at: destination)
        return destination
    }

    /// Wspólna walidacja dla `videoURL` tutaj i `LivePhotoVideoExtractor.
    /// pairedVideoURL` — plik istnieje i `writeData` nie zwrócił błędu, ale
    /// to jeszcze nie znaczy że da się go użyć w kompozycji.
    static func validatePlayableVideo(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard duration.isValid, duration.seconds > 0, tracks.contains(where: { $0.mediaType == .video }) else {
            throw LoadError.videoResourceNotFound
        }
    }

    /// UWAGA: mimo nazwy, ten sam zwrócony obraz karmi też finalny eksport
    /// wideo (`VideoComposer.resolveSourceURL` → `ImageToVideoRenderer`), nie
    /// tylko siatkę miniaturek — dlatego `targetSize: PHImageManagerMaximumSize`
    /// (pełna oryginalna rozdzielczość), NIE mała miniaturka. Wcześniej było
    /// tu 300×300 — świetne do siatki, ale przy ponownym otwarciu zapisanego
    /// projektu ten sam malutki obrazek był rozciągany do pełnej
    /// rozdzielczości kanwy eksportu (np. 2160×3840 przy 4K), dając wyraźnie
    /// gorszą jakość niż przy pierwszym wyborze zdjęć (user: "zdjęcia nie są
    /// już tej samej jakości" po ponownym wejściu w edycję).
    /// `contentMode` jest ignorowane przez `PHImageManager` przy
    /// `PHImageManagerMaximumSize` (zwraca zawsze oryginalny kadr) — zgodnie
    /// z zasadą "żadnego przycinania" reszty appki.
    static func thumbnail(forAssetLocalIdentifier identifier: String) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // 30.08.2026 — ta sama naprawa co `MediaItemLoader.downsampledImage`:
        // `PHImageManagerMaximumSize` zwraca zdjęcie w PEŁNEJ rozdzielczości
        // źródła tylko po to, żeby zrobić z niego miniaturkę osi czasu —
        // przy projekcie z wieloma elementami (np. ~140) to samo ryzyko
        // cichego zabicia appki przez iOS (jetsam) przy PONOWNYM otwarciu
        // już zapisanego projektu, nie tylko przy pierwszym imporcie.
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 640, height: 640),
                contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Zdjęcie w PEŁNEJ rozdzielczości źródła — WYŁĄCZNIE dla faktycznego
    /// renderu eksportu (`VideoComposer.resolveSourceURL`/
    /// `resolveOverlaySourceURL` → `ImageToVideoRenderer`), NIGDY dla
    /// wyświetlania w UI (do tego służy mała `thumbnail(forAssetLocalIdentifier:)`
    /// wyżej). Rozdzielone 30.08.2026 — wcześniej export używał WPROST
    /// `MediaItem.thumbnail`/`OverlayItem.thumbnail`, więc zmniejszenie tamtej
    /// miniaturki (naprawa cichego zabijania appki przez iOS przy dużych
    /// selekcjach, patrz `thumbnail(forAssetLocalIdentifier:)`) po cichu
    /// przywróciło DOKŁADNIE ten sam bug jakości co 29.07.2026 ("zdjęcia nie
    /// są już tej samej jakości") — komentarz przy `thumbnail(forAssetLocalIdentifier:)`
    /// nawet o tym ostrzegał, przeoczony przy tamtej naprawie. Bezpieczne
    /// pamięciowo mimo pełnej rozdzielczości: `VideoComposer.resolveSourceURLs`
    /// renderuje zdjęcia SEKWENCYJNIE (`maxConcurrent = 1`), więc w pamięci
    /// jest naraz najwyżej JEDEN taki obraz, nie wszystkie zdjęcia projektu.
    static func fullResolutionImage(forAssetLocalIdentifier identifier: String) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Pierwsza dostępna lokalizacja GPS spośród wybranych zasobów — używana
    /// do automatycznego nazwania projektu miejscem zamiast samej daty.
    /// Zdjęcia z jednego wyboru w pickerze są zwykle z tej samej okazji/
    /// miejsca, więc pierwsza napotkana lokalizacja wystarcza — nie trzeba
    /// liczyć "najczęstszej" spośród wielu.
    static func firstLocation(forAssetLocalIdentifiers identifiers: [String]) -> CLLocation? {
        guard !identifiers.isEmpty else { return nil }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var found: CLLocation?
        fetchResult.enumerateObjects { asset, _, stop in
            if let location = asset.location {
                found = location
                stop.pointee = true
            }
        }
        return found
    }

    /// Najwcześniejsza data spośród zdjęć/wideo projektu — 04.08.2026, user:
    /// Library ma grupować projekty wg roku PODRÓŻY, nie wg tego kiedy
    /// projekt został utworzony/edytowany w appce ("bez znaczenia czy
    /// edytowaliśmy, a znaczenie kiedy mieliśmy te memories"). Ten sam
    /// wzorzec co `firstLocation` (auto-nazwa z GPS) — prawdziwe metadane
    /// zdjęcia zamiast metadanych appki. Najwcześniejsza (nie pierwsza
    /// napotkana) data, żeby kolejność wybierania w pickerze nie wpływała
    /// na wynik.
    static func earliestCreationDate(forAssetLocalIdentifiers identifiers: [String]) -> Date? {
        guard !identifiers.isEmpty else { return nil }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var earliest: Date?
        fetchResult.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            if earliest == nil || date < earliest! { earliest = date }
        }
        return earliest
    }

    /// Jak `firstLocation`, ale zbiera identyfikator+lokalizację+datę KAŻDEGO
    /// zdjęcia (nie tylko pierwszej napotkanej) — potrzebne dla Smart Route,
    /// gdzie trasa musi być odtworzona z WSZYSTKICH wybranych zdjęć, nie z
    /// jednego. Identyfikator dociągnięty 30.07.2026 obok lokalizacji/daty —
    /// Smart Route zapamiętuje który konkretnie plik reprezentuje każdy
    /// wykryty przystanek, do miniaturki na markerze.
    static func locationsAndDates(forAssetLocalIdentifiers identifiers: [String]) -> [(identifier: String, location: CLLocation, date: Date?)] {
        guard !identifiers.isEmpty else { return [] }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var results: [(identifier: String, location: CLLocation, date: Date?)] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if let location = asset.location {
                results.append((asset.localIdentifier, location, asset.creationDate))
            }
        }
        return results
    }

    /// Mała miniaturka do markera na mapie — w odróżnieniu od `thumbnail`
    /// wyżej CELOWO mały `targetSize` (marker to kilkadziesiąt punktów, nie
    /// pełnoekranowy kadr eksportu), żeby nie ściągać pełnej rozdzielczości
    /// zdjęcia tylko po to, żeby ją zaraz zmniejszyć do kropki na mapie.
    static func markerThumbnail(forAssetLocalIdentifier identifier: String) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 160, height: 160),
                contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Odtwarza pełną listę `MediaItem` z zapisanych rekordów `SavedMediaItem`
    /// (posortowanych po `order`) — miniaturki i pliki wideo pobierane na
    /// nowo z biblioteki Photos po `assetLocalIdentifier`.
    static func loadMediaItems(from saved: [SavedMediaItem], onProgress: ((Double) -> Void)? = nil) async -> [MediaItem] {
        var result: [MediaItem] = []
        let sorted = saved.sorted(by: { $0.order < $1.order })
        let total = sorted.count
        for (index, record) in sorted.enumerated() {
            let thumbnail = await thumbnail(forAssetLocalIdentifier: record.assetLocalIdentifier)

            var pairedVideoURL: URL?
            if record.isLivePhoto {
                pairedVideoURL = try? await LivePhotoVideoExtractor.pairedVideoURL(
                    forAssetLocalIdentifier: record.assetLocalIdentifier
                )
            }

            var resolvedVideoURL: URL?
            if record.isVideo {
                resolvedVideoURL = try? await videoURL(forAssetLocalIdentifier: record.assetLocalIdentifier)
            }

            var sourceDuration: Double?
            if let sourceURL = resolvedVideoURL ?? pairedVideoURL {
                sourceDuration = try? await AVURLAsset(url: sourceURL).load(.duration).seconds
            }

            result.append(MediaItem(
                pickerItemId: record.assetLocalIdentifier,
                isLivePhoto: record.isLivePhoto,
                isVideo: record.isVideo,
                thumbnail: thumbnail,
                useMotion: record.useMotion,
                pairedVideoURL: pairedVideoURL,
                videoURL: resolvedVideoURL,
                duration: record.duration,
                trimStart: record.trimStart,
                sourceDuration: sourceDuration,
                isManuallyTrimmed: record.isManuallyTrimmed,
                speed: record.speed,
                rotationDegrees: record.rotationDegrees,
                cropFill: record.cropFill,
                originalVolume: record.originalVolume,
                transitionStyle: record.transitionStyleRawValue.flatMap(TransitionStyle.init(rawValue:))
            ))
            onProgress?(Double(index + 1) / Double(max(1, total)))
        }
        return result
    }

    /// Analogicznie do `loadMediaItems`, dla nakładek PiP (`SavedOverlayItem`
    /// → `OverlayItem`) — ten sam wzorzec odtwarzania miniaturki/pliku wideo
    /// z samego `assetLocalIdentifier`.
    static func loadOverlayItems(from saved: [SavedOverlayItem]) async -> [OverlayItem] {
        var result: [OverlayItem] = []
        let sorted = saved.sorted(by: { $0.order < $1.order })
        for record in sorted {
            let thumbnail = await thumbnail(forAssetLocalIdentifier: record.assetLocalIdentifier)

            var pairedVideoURL: URL?
            if record.isLivePhoto {
                pairedVideoURL = try? await LivePhotoVideoExtractor.pairedVideoURL(
                    forAssetLocalIdentifier: record.assetLocalIdentifier
                )
            }

            var resolvedVideoURL: URL?
            if record.isVideo {
                resolvedVideoURL = try? await videoURL(forAssetLocalIdentifier: record.assetLocalIdentifier)
            }

            result.append(OverlayItem(
                pickerItemId: record.assetLocalIdentifier,
                isLivePhoto: record.isLivePhoto,
                isVideo: record.isVideo,
                thumbnail: thumbnail,
                useMotion: record.useMotion,
                pairedVideoURL: pairedVideoURL,
                videoURL: resolvedVideoURL,
                globalStartTime: record.globalStartTime,
                duration: record.duration,
                corner: OverlayCorner(rawValue: record.cornerRawValue) ?? .bottomTrailing,
                sizeScale: record.sizeScale
            ))
        }
        return result
    }
}
