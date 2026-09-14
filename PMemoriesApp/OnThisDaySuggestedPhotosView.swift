import SwiftUI
import Photos
import AVKit
import UIKit

/// 05.09.2026 — user: "apka ma dostęp do zdjęć nie może tego sama sobie
/// znaleźć?" — zamiast otwierać cały systemowy `PhotosPicker` (cała
/// biblioteka, user musi ręcznie przewijać do konkretnej podróży sprzed lat),
/// appka SAMA odpytuje `PHAsset` po dacie tego przystanku i pokazuje TYLKO
/// znalezione zdjęcia/wideo. Świadomie CZYSTA GALERIA do przeglądania, BEZ
/// zaznaczania i BEZ tworzenia nowego Memory — pierwsza wersja prowadziła
/// zaznaczone zdjęcia do `pickerSelection` → `loadSelection` (Studio), ale
/// user: "nie rozumiem po co mnie to przenosi do studia nie chce nic
/// tworzyc... lepiej by bylo pokazac wszystkie zdjecia z tego okresu" —
/// usunięte całe zaznaczanie/potok tworzenia, zostaje tylko siatka + pełny
/// podgląd na tapnięcie.
struct OnThisDaySuggestedPhotosView: View {
    let dateRange: ClosedRange<Date>

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var authorizationDenied = false
    @State private var viewerIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if authorizationDenied {
                    ContentUnavailableView(
                        L("No access to Photos"),
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(L("Allow full Photos access in Settings to see suggestions."))
                    )
                } else if assets.isEmpty {
                    ContentUnavailableView(
                        L("No photos found from this trip"),
                        systemImage: "photo.stack",
                        description: Text(L("Nothing on this device matches that date range."))
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                OnThisDayAssetThumbnail(asset: asset)
                                    .onTapGesture { viewerIndex = index }
                            }
                        }
                        .padding(3)
                    }
                }
            }
            .navigationTitle(L("Photos from this trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .task { await loadAssets() }
            .fullScreenCover(item: $viewerIndex.animation(), content: { index in
                OnThisDayFullScreenViewer(assets: assets, startIndex: index)
            })
        }
    }

    private func loadAssets() async {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized || status == .limited else {
            authorizationDenied = true
            isLoading = false
            return
        }
        // UWAGA (05.09.2026, realny bug): złożony `NSPredicate` z dwoma
        // warunkami na TYM SAMYM polu ("creationDate >= %@ AND creationDate
        // <= %@") jest znanym, udokumentowanym problemem `PHFetchOptions` —
        // bywa po cichu ignorowany i `fetchAssets` zwraca CAŁĄ bibliotekę
        // zamiast przefiltrowanej. Zamiast polegać na predykacie Photos
        // framework, filtrujemy RĘCZNIE po `asset.creationDate` w Swift —
        // wolniejsze o ułamek sekundy (enumeracja jest leniwa, nie ładuje
        // pikseli), ale niezawodne.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var found: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate, dateRange.contains(created) else { return }
            found.append(asset)
        }
        assets = found
        isLoading = false
    }
}

/// `Int` nie jest domyślnie `Identifiable` — `.fullScreenCover(item:)`
/// wymaga tego do prezentacji z konkretnym indeksem startowym (żeby
/// otworzyć na TYM zdjęciu które user tapnął, nie zawsze od zera).
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

private struct OnThisDayAssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 92, height: 92)
            .clipped()

            if asset.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .task {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 184, height: 184),
                contentMode: .aspectFill, options: options
            ) { img, _ in
                if let img { image = img }
            }
        }
    }
}

/// Pełnoekranowa, przewijalna (swipe) galeria — sam podgląd, zero akcji
/// tworzenia. Ten sam duch co systemowa appka Zdjęcia: tap na miniaturkę →
/// pełny ekran na TYM zdjęciu, swipe do sąsiednich.
private struct OnThisDayFullScreenViewer: View {
    let assets: [PHAsset]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(assets: [PHAsset], startIndex: Int) {
        self.assets = assets
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    OnThisDayFullScreenAsset(asset: asset).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            .padding()
        }
    }
}

private struct OnThisDayFullScreenAsset: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if asset.mediaType == .video, let player {
                VideoPlayer(player: player)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.deliveryMode = .automatic
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                    guard let item else { return }
                    Task { @MainActor in player = AVPlayer(playerItem: item) }
                }
            } else {
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                PHImageManager.default().requestImage(
                    for: asset, targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit, options: options
                ) { img, _ in
                    if let img { image = img }
                }
            }
        }
    }
}
