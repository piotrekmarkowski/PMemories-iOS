import Foundation
import Photos

/// Wyciąga wideo część (`pairedVideo`) z Live Photo, żeby użyć jej jako
/// zwykłego klipu w kompozycji zamiast statycznego zdjęcia.
enum LivePhotoVideoExtractor {
    enum ExtractionError: Error {
        case assetNotFound
        case pairedVideoResourceNotFound
    }

    static func pairedVideoURL(forAssetLocalIdentifier identifier: String) async throws -> URL {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw ExtractionError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            throw ExtractionError.pairedVideoResourceNotFound
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: videoResource,
                toFile: destination,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // 23.08.2026 — ta sama walidacja co `MediaAssetLoader.videoURL`
        // (patrz komentarz tam): `writeData` bez błędu nie gwarantuje
        // kompletnego, odtwarzalnego pliku.
        do {
            try await MediaAssetLoader.validatePlayableVideo(at: destination)
        } catch {
            throw ExtractionError.pairedVideoResourceNotFound
        }

        return destination
    }
}
