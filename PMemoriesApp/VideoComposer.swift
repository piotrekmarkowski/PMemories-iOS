import AVFoundation
import QuartzCore
import UIKit
import CoreText

/// Skleja uporządkowaną listę elementów (zdjęcia/wideo/Live Photo) i
/// opcjonalną muzykę w jedną kompozycję gotową do eksportu.
enum VideoComposer {
    enum ComposerError: Error {
        case videoTrackCreationFailed
        case noUsableItems
    }

    /// Kompozycja (klipy + audio w czasie), instrukcje renderowania
    /// (transformy per-klip: obrót/crop) i mix audio (poziomy głośności
    /// oryginalnego dźwięku klipów + muzyki) — `AVAssetExportSession`
    /// potrzebuje wszystkich trzech, żeby zastosować Rotate/Crop/głośność.
    struct ComposedProject {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix?
    }

    /// Jeden umieszczony na timeline klip — potrzebne osobno od samego
    /// wstawiania, bo instrukcje renderowania (solo/przejście) budujemy w
    /// DRUGIM przebiegu, dopiero gdy znamy pozycje WSZYSTKICH klipów.
    private struct ClipPlacement {
        let track: AVMutableCompositionTrack
        let start: CMTime
        let duration: CMTime
        let transform: CGAffineTransform
    }

    /// Jedna umieszczona nakładka "picture-in-picture" — Faza 1 "prawdziwego
    /// multi-tracku" (patrz `Docs/Studio.md`). Osobny, mały tor NAD głównym
    /// timeline'em, zawsze wyciszony, zawsze pełny czas źródła od początku
    /// (bez trim/speed/rotate/crop — świadomie poza zakresem Fazy 1).
    private struct OverlayPlacement {
        let track: AVMutableCompositionTrack
        let range: CMTimeRange
        let transform: CGAffineTransform
    }

    /// Czas trwania crossfade między dwoma klipami — stały, nieedytowalny
    /// (user: "dodaj teraz prosty crossfade", bez prośby o kontrolę per-klip,
    /// więc nie dokładamy UI, którego nikt nie prosił).
    /// NIE `private` — `EditView.redistributeDurations()` potrzebuje tej
    /// wartości do rekompensaty: crossfade NAKŁADA się na sąsiednie klipy
    /// (nie dodaje czasu), więc bez korekty suma `duration` wszystkich
    /// klipów równa długości utworu i tak dałaby finalny film KRÓTSZY o
    /// (liczba przejść) × czas przejścia.
    static let transitionDuration = CMTime(seconds: 0.4, preferredTimescale: 600)

    static func buildComposition(
        items: [MediaItem], audioURL: URL?, musicVolume: Double = 1.0, captions: [Caption] = [],
        overlays: [OverlayItem] = [],
        quality: ExportQuality = .hd1080,
        enabledTransitionStyles: [TransitionStyle] = TransitionStyle.allCases,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ComposedProject {
        // Canvas skalowany wg wybranej jakości eksportu — Rotate/Crop
        // potrzebują JEDNEGO wspólnego rozmiaru docelowego (dla wszystkich
        // klipów), żeby transformy miały sens; to ten sam rozmiar, tylko
        // teraz konfigurowalny zamiast zaszytego na sztywno w 1080x1920.
        let canvasSize = quality.canvasSize
        let composition = AVMutableComposition()
        // DWA tory wideo (i dwa audio oryginalnego dźwięku) zamiast jednego —
        // crossfade wymaga, żeby dwa sąsiednie klipy przez chwilę odtwarzały
        // się RÓWNOCZEŚNIE (jeden gaśnie, drugi się pojawia), a pojedynczy
        // `AVMutableCompositionTrack` nie pozwala na nakładające się zakresy
        // czasu. Klipy na przemian trafiają na tor A/B (user feedback
        // 27.07.2026: "przejścia są tragiczne, zwykłe proste").
        guard let videoTrackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ComposerError.videoTrackCreationFailed
        }
        let originalAudioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let originalAudioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var placements: [ClipPlacement] = []
        // transitionDurations[i] = długość przejścia MIĘDZY placements[i] a
        // placements[i+1] (o jeden element krócej niż placements).
        var transitionDurations: [CMTime] = []
        // transitionStyles[i] = styl przejścia dla TEJ SAMEJ pary co
        // transitionDurations[i] — `MediaItem.transitionStyle` przychodzącego
        // klipu (`nil` = auto, appka sama dobiera w `buildInstructions`).
        var transitionStyles: [TransitionStyle?] = []
        var originalVolumeSegments: [(trackIndex: Int, range: CMTimeRange, volume: Float)] = []
        var previousDuration: CMTime?
        var timelineEnd = CMTime.zero
        // Dokąd ma sięgać ścieżka muzyczna — zwykle to samo co `timelineEnd`,
        // ale PRZESTAJE się posuwać, gdy trafimy na element oznaczony
        // `mutesBackgroundMusic` (12.08.2026, karta brandingowa PMemories na
        // końcu eksportu ma grać w ciszy, nie pod muzykę). Takie elementy są
        // zawsze na SAMYM końcu, więc to poprawnie łapie moment TUŻ PRZED
        // pierwszym z nich.
        var musicTimelineEnd = CMTime.zero

        // `resolveSourceURL` per zdjęcie robi pełne, niezależne renderowanie
        // (`ImageToVideoRenderer` — osobna sesja `AVAssetWriter`), ale pętla
        // PONIŻEJ, budująca kompozycję, musi zostać sekwencyjna (kolejny
        // `placementStart` zależy od poprzednich elementów). Rozwiązujemy
        // więc wszystkie źródła RÓWNOLEGLE najpierw (ograniczone do 4 na
        // raz — bez limitu przy 60+ zdjęciach zbyt duże obciążenie CPU/
        // pamięci naraz, zwłaszcza na starszych telefonach), dopiero potem
        // budujemy kompozycję z gotowych URL-i. Przy wielu zdjęciach to był
        // największy pojedynczy czynnik spowalniający eksport (user:
        // "importowanie zdjęć... trwa wieczność").
        let resolvedSourceURLs = try await resolveSourceURLs(for: items, canvasSize: canvasSize, onProgress: onProgress)

        for (index, item) in items.enumerated() {
            guard let sourceURL = resolvedSourceURLs[index] else { continue }

            let asset = AVURLAsset(url: sourceURL)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }

            let assetDuration = try await asset.load(.duration)
            // trimStart > 0 tylko dla klipów faktycznie przyciętych w Trim —
            // przycięty do granic źródła, żeby nie wyjść poza koniec assetu.
            let clampedTrimStart = max(0, min(item.trimStart, assetDuration.seconds))
            let trimStartTime = CMTime(seconds: clampedTrimStart, preferredTimescale: 600)
            let availableDuration = assetDuration - trimStartTime

            // `item.duration` to zawsze docelowy czas w finalnym filmiku —
            // przy speed != 1.0 trzeba zużyć więcej/mniej sekund ŹRÓDŁA, żeby
            // po przyspieszeniu/zwolnieniu wyszło dokładnie tyle. Insertujemy
            // surowy fragment źródła w naturalnym tempie, potem `scaleTimeRange`
            // ściska/rozciąga go do właściwej długości na timeline.
            let speed = item.speed > 0 ? item.speed : 1.0
            let desiredSourceDuration = CMTime(seconds: item.duration * speed, preferredTimescale: 600)
            let sourceRangeDuration = min(availableDuration, desiredSourceDuration)
            guard sourceRangeDuration > .zero else { continue }

            let outputDuration: CMTime = speed != 1.0
                ? CMTime(seconds: sourceRangeDuration.seconds / speed, preferredTimescale: 600)
                : sourceRangeDuration

            let isFirst = placements.isEmpty
            var transitionBefore = CMTime.zero
            if !isFirst, let prevDuration = previousDuration {
                // Nie dłuższe niż połowa KRÓTSZEGO z dwóch sąsiadujących
                // klipów — żeby przy bardzo krótkich klipach przejście nie
                // "zjadło" całego sąsiada.
                let maxAllowed = min(prevDuration, outputDuration).seconds / 2
                transitionBefore = CMTime(seconds: min(transitionDuration.seconds, maxAllowed), preferredTimescale: 600)
            }
            let placementStart = isFirst ? .zero : timelineEnd - transitionBefore

            let trackIndex = index % 2
            let videoTrack = trackIndex == 0 ? videoTrackA : videoTrackB
            let audioTrack = trackIndex == 0 ? originalAudioTrackA : originalAudioTrackB

            let sourceRange = CMTimeRange(start: trimStartTime, duration: sourceRangeDuration)
            try videoTrack.insertTimeRange(sourceRange, of: assetTrack, at: placementStart)
            if speed != 1.0 {
                videoTrack.scaleTimeRange(CMTimeRange(start: placementStart, duration: sourceRangeDuration), toDuration: outputDuration)
            }

            // Ten sam zakres co wideo — jeśli źródło ma ścieżkę dźwiękową
            // (zwykłe wideo/Live Photo z ruchem; syntetyczne wideo ze zdjęcia
            // nie ma), wstawiamy ją i skalujemy dokładnie tak samo, żeby
            // zostać w synchronizacji z przyspieszonym/zwolnionym obrazem.
            // Naprzemienne tory A/B jak wideo — przy okazji audio też się
            // ładnie przenika podczas crossfade zamiast twardo urywać.
            if let audioTrack, let audioAssetTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(sourceRange, of: audioAssetTrack, at: placementStart)
                if speed != 1.0 {
                    audioTrack.scaleTimeRange(CMTimeRange(start: placementStart, duration: sourceRangeDuration), toDuration: outputDuration)
                }
                originalVolumeSegments.append((trackIndex, CMTimeRange(start: placementStart, duration: outputDuration), Float(item.originalVolume)))
            }

            let naturalSize = try await assetTrack.load(.naturalSize)
            let preferredTransform = try await assetTrack.load(.preferredTransform)
            let transform = layerTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                rotationDegrees: item.rotationDegrees,
                cropFill: item.cropFill,
                canvasSize: canvasSize
            )

            if !isFirst {
                transitionDurations.append(transitionBefore)
                transitionStyles.append(item.transitionStyle)
            }
            placements.append(ClipPlacement(track: videoTrack, start: placementStart, duration: outputDuration, transform: transform))
            timelineEnd = placementStart + outputDuration
            if !item.mutesBackgroundMusic {
                musicTimelineEnd = timelineEnd
            }
            previousDuration = outputDuration
        }

        guard !placements.isEmpty else {
            throw ComposerError.noUsableItems
        }

        // Tor nakładki "picture-in-picture" — Faza 1 "prawdziwego
        // multi-tracku" (patrz Docs/Studio.md). JEDEN tor (nie naprzemienne
        // A/B jak główny tor) — Faza 1 celowo zakazuje nakładek nachodzących
        // na siebie NAWZAJEM w czasie, więc pojedynczy tor wystarcza. Zero
        // toru audio dla nakładek — to gwarantuje ciszę "konstrukcyjnie", nie
        // przez flagę do pamiętania.
        var overlayPlacements: [OverlayPlacement] = []
        if !overlays.isEmpty,
           let overlayTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            for overlay in overlays {
                guard let sourceURL = try await resolveOverlaySourceURL(for: overlay, canvasSize: canvasSize) else { continue }
                let asset = AVURLAsset(url: sourceURL)
                guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let assetDuration = try await asset.load(.duration)
                let clampedDuration = min(CMTime(seconds: overlay.duration, preferredTimescale: 600), assetDuration)
                guard clampedDuration > .zero else { continue }

                let start = CMTime(seconds: overlay.globalStartTime, preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: .zero, duration: clampedDuration)
                try overlayTrack.insertTimeRange(sourceRange, of: assetTrack, at: start)

                let naturalSize = try await assetTrack.load(.naturalSize)
                let preferredTransform = try await assetTrack.load(.preferredTransform)
                let transform = overlayTransform(
                    naturalSize: naturalSize, preferredTransform: preferredTransform,
                    corner: overlay.corner, sizeScale: overlay.sizeScale, canvasSize: canvasSize
                )
                overlayPlacements.append(OverlayPlacement(
                    track: overlayTrack, range: CMTimeRange(start: start, duration: clampedDuration), transform: transform
                ))
            }
        }

        var musicTrack: AVMutableCompositionTrack?
        if let audioURL {
            let audioAsset = AVURLAsset(url: audioURL)
            if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let audioDuration = try await audioAsset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: min(audioDuration, musicTimelineEnd))
                try compositionAudioTrack.insertTimeRange(range, of: audioAssetTrack, at: .zero)
                musicTrack = compositionAudioTrack
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvasSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        var instructions = buildInstructions(placements: placements, transitionDurations: transitionDurations, transitionStyles: transitionStyles, canvasSize: canvasSize, enabledTransitionStyles: enabledTransitionStyles)
        // Nakładanie nakładek PiP jako OSOBNY przebieg NAD już zbudowanymi
        // instrukcjami — `buildInstructions` (crossfade między głównymi
        // klipami) zostaje całkowicie nietknięte, niższe ryzyko niż wplatanie
        // świadomości nakładek prosto w logikę przejść.
        for overlay in overlayPlacements {
            let snapped = snapOverlayRange(overlay.range, avoiding: instructions)
            instructions = applyOverlay(to: instructions, overlay: OverlayPlacement(track: overlay.track, range: snapped, transform: overlay.transform), placements: placements)
        }
        videoComposition.instructions = instructions
        if !captions.isEmpty {
            videoComposition.animationTool = animationTool(captions: captions, canvasSize: canvasSize)
        }

        let audioMix = buildAudioMix(
            originalAudioTrackA: originalVolumeSegments.contains { $0.trackIndex == 0 } ? originalAudioTrackA : nil,
            originalAudioTrackB: originalVolumeSegments.contains { $0.trackIndex == 1 } ? originalAudioTrackB : nil,
            originalVolumeSegments: originalVolumeSegments,
            musicTrack: musicTrack,
            musicVolume: Float(musicVolume)
        )

        return ComposedProject(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// Buduje instrukcje renderowania z umieszczonych klipów: dla każdego
    /// klipu jego "solo" odcinek (jedna warstwa) plus, między sąsiadującymi
    /// klipami, odcinek przejścia (dwie warstwy — wchodzący klip narasta z
    /// przezroczystości 0→1 NAD gasnącym poprzednim 1→0). Standardowy wzorzec
    /// AVFoundation na crossfade (dwa tory + rampa przezroczystości), nie
    /// wymaga dodatkowej ramki na klip jak prawdziwy multi-track.
    private static func buildInstructions(
        placements: [ClipPlacement],
        transitionDurations: [CMTime],
        transitionStyles: [TransitionStyle?],
        canvasSize: CGSize,
        enabledTransitionStyles: [TransitionStyle] = TransitionStyle.allCases
    ) -> [AVMutableVideoCompositionInstruction] {
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for i in 0..<placements.count {
            let placement = placements[i]
            let transitionBefore = i > 0 ? transitionDurations[i - 1] : .zero
            let transitionAfter = i < placements.count - 1 ? transitionDurations[i] : .zero

            let soloStart = placement.start + transitionBefore
            let soloEnd = placement.start + placement.duration - transitionAfter
            if soloEnd > soloStart {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: soloStart, end: soloEnd)
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: placement.track)
                layer.setTransform(placement.transform, at: soloStart)
                instruction.layerInstructions = [layer]
                instructions.append(instruction)
            }

            guard i < placements.count - 1 else { continue }
            let t = transitionDurations[i]
            guard t > .zero else { continue }
            let next = placements[i + 1]
            let transitionStart = next.start
            let transitionEnd = placement.start + placement.duration
            let transitionRange = CMTimeRange(start: transitionStart, duration: t)
            let style = transitionStyles[i] ?? TransitionStyle.auto(forTransitionIndex: i, pool: enabledTransitionStyles)

            let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: next.track)
            let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: placement.track)
            applyTransition(
                style: style, incoming: incoming, outgoing: outgoing,
                incomingTransform: next.transform, outgoingTransform: placement.transform,
                transitionStart: transitionStart, transitionRange: transitionRange, canvasSize: canvasSize
            )

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: transitionStart, end: transitionEnd)
            // Wchodzący klip pierwszy = na wierzchu (kolejność w tablicy to
            // przód→tył w AVFoundation).
            instruction.layerInstructions = [incoming, outgoing]
            instructions.append(instruction)
        }

        return instructions
    }

    /// Ustawia rampy (transform/opacity) na dwóch warstwach przejścia wg
    /// wybranego stylu — WSZYSTKIE style celowo ograniczone do tego co potrafi
    /// zwykła `AVMutableVideoCompositionLayerInstruction` (transform/opacity
    /// ramp), bez custom `AVVideoCompositing` (świadomie odrzucone wcześniej
    /// jako zbyt duży, osobny temat — patrz komentarz przy `transitionDuration`).
    private static func applyTransition(
        style: TransitionStyle,
        incoming: AVMutableVideoCompositionLayerInstruction,
        outgoing: AVMutableVideoCompositionLayerInstruction,
        incomingTransform: CGAffineTransform,
        outgoingTransform: CGAffineTransform,
        transitionStart: CMTime,
        transitionRange: CMTimeRange,
        canvasSize: CGSize
    ) {
        // Wspólne dla kilku stylów (09.08.2026, rozbudowa 3→10) — środek
        // kanwy do skalowania/obrotu WOKÓŁ ŚRODKA (nie wokół lewego górnego
        // rogu, domyślnego punktu odniesienia transformów), i dwa helpery na
        // bazie DOKŁADNIE tego samego wzorca co istniejący `.zoom` niżej.
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        func scaled(_ transform: CGAffineTransform, x factorX: CGFloat, y factorY: CGFloat) -> CGAffineTransform {
            let aroundCenter = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: factorX, y: factorY)
                .translatedBy(x: -center.x, y: -center.y)
            return transform.concatenating(aroundCenter)
        }
        func rotated(_ transform: CGAffineTransform, by angle: CGFloat) -> CGAffineTransform {
            let aroundCenter = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y)
            return transform.concatenating(aroundCenter)
        }

        switch style {
        case .crossfade:
            incoming.setTransform(incomingTransform, at: transitionStart)
            incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)

        case .slide:
            // "Push": wchodzący klip wjeżdża z prawej krawędzi kanwy na
            // wierzchu, wychodzący zostaje nieruchomy pod spodem (zostaje
            // zasłonięty, nie gaśnie) — inny efekt niż crossfade, bez
            // przezroczystości.
            let offscreenStart = incomingTransform.concatenating(CGAffineTransform(translationX: canvasSize.width, y: 0))
            incoming.setTransformRamp(fromStart: offscreenStart, toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)

        case .slideLeft:
            // Lustrzane odbicie `.slide` — wjazd z LEWEJ krawędzi.
            let offscreenStart = incomingTransform.concatenating(CGAffineTransform(translationX: -canvasSize.width, y: 0))
            incoming.setTransformRamp(fromStart: offscreenStart, toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)

        case .slideUp:
            // Wjazd z DOŁU (ruch w górę na ekranie) — ten sam wzorzec co
            // `.slide`, tylko oś Y zamiast X.
            let offscreenStart = incomingTransform.concatenating(CGAffineTransform(translationX: 0, y: canvasSize.height))
            incoming.setTransformRamp(fromStart: offscreenStart, toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)

        case .slideDown:
            // Wjazd z GÓRY (ruch w dół na ekranie).
            let offscreenStart = incomingTransform.concatenating(CGAffineTransform(translationX: 0, y: -canvasSize.height))
            incoming.setTransformRamp(fromStart: offscreenStart, toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)

        case .zoom:
            // Wchodzący klip powiększa się z 85% do pełnego rozmiaru + fade
            // in; wychodzący jednocześnie delikatnie powiększa się do 115% +
            // fade out — subtelny efekt "wjazdu przez obiektyw", inny rytm
            // niż płaski crossfade.
            incoming.setTransformRamp(fromStart: scaled(incomingTransform, x: 0.85, y: 0.85), toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransformRamp(fromStart: outgoingTransform, toEnd: scaled(outgoingTransform, x: 1.15, y: 1.15), timeRange: transitionRange)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)

        case .zoomOut:
            // Lustrzane odbicie `.zoom` w dynamice — wchodzący ZMNIEJSZA się
            // ze 115% do pełnego rozmiaru (wjazd "z bliska"), wychodzący
            // kurczy się do 85% + fade out.
            incoming.setTransformRamp(fromStart: scaled(incomingTransform, x: 1.15, y: 1.15), toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransformRamp(fromStart: outgoingTransform, toEnd: scaled(outgoingTransform, x: 0.85, y: 0.85), timeRange: transitionRange)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)

        case .rotate:
            // Delikatny obrót (±7°) wokół środka kanwy + fade — inny rytm niż
            // czysto liniowe skalowanie/przesunięcie.
            let angle: CGFloat = 7 * .pi / 180
            incoming.setTransformRamp(fromStart: rotated(incomingTransform, by: -angle), toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransformRamp(fromStart: outgoingTransform, toEnd: rotated(outgoingTransform, by: angle), timeRange: transitionRange)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)

        case .squeeze:
            // "Ściśnięcie" w poziomie — skalowanie TYLKO osi X do 0 (klip
            // znika/pojawia się jak zamykana/otwierana zasłona), oś Y bez
            // zmian. Czysto geometryczny efekt, bez opacity (jak `.slide`) —
            // przy scaleX≈0 i tak nic nie widać.
            incoming.setTransformRamp(fromStart: scaled(incomingTransform, x: 0.001, y: 1), toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransformRamp(fromStart: outgoingTransform, toEnd: scaled(outgoingTransform, x: 0.001, y: 1), timeRange: transitionRange)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 1, timeRange: transitionRange)

        case .diagonal:
            // Wjazd po przekątnej (prawy dolny róg) + fade — hybryda
            // `.slide`/`.crossfade`.
            let offscreenStart = incomingTransform.concatenating(
                CGAffineTransform(translationX: canvasSize.width, y: canvasSize.height)
            )
            incoming.setTransformRamp(fromStart: offscreenStart, toEnd: incomingTransform, timeRange: transitionRange)
            incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            outgoing.setTransform(outgoingTransform, at: transitionStart)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)
        }
    }

    /// Odsuwa granice zakresu nakładki PiP tak, żeby nigdy nie zaczynały/
    /// kończyły się ŚCIŚLE wewnątrz instrukcji przejścia (crossfade) — te
    /// instrukcje niosą `setOpacityRamp` liczoną na CAŁY swój zakres, więc
    /// ich przecinanie wymagałoby ponownego wyliczenia częściowej rampy
    /// (realna złożoność za mały zysk w Fazie 1). W najgorszym razie granica
    /// nakładki przesuwa się o ~0.4s (długość przejścia) — niezauważalne.
    private static func snapOverlayRange(_ range: CMTimeRange, avoiding instructions: [AVMutableVideoCompositionInstruction]) -> CMTimeRange {
        var start = range.start
        var end = range.end
        for instruction in instructions where instruction.layerInstructions.count == 2 {
            let transitionRange = instruction.timeRange
            if start > transitionRange.start && start < transitionRange.end {
                start = (start - transitionRange.start) < (transitionRange.end - start) ? transitionRange.start : transitionRange.end
            }
            if end > transitionRange.start && end < transitionRange.end {
                end = (end - transitionRange.start) < (transitionRange.end - end) ? transitionRange.start : transitionRange.end
            }
        }
        guard end > start else { return range }
        return CMTimeRange(start: start, end: end)
    }

    /// Nakłada JEDNĄ nakładkę PiP na już zbudowane instrukcje renderowania —
    /// osobny, drugi przebieg NAD `buildInstructions`, żeby logika crossfade
    /// między głównymi klipami zostawała całkowicie nietknięta.
    ///
    /// Instrukcje "solo" (1 warstwa — bez rampy do zachowania) są bezpieczne
    /// do pocięcia na maks. 3 kawałki (przed/w trakcie/po) wokół nakładki;
    /// `AVMutableVideoCompositionLayerInstruction` nie ma gettera do
    /// odczytania transformu/toru z którym `setTransform` już wywołano, więc
    /// oryginalny `ClipPlacement` odtwarzamy przez dopasowanie zakresu
    /// czasowego instrukcji do zakresu placementu, który go zawiera.
    ///
    /// Instrukcje przejścia (2 warstwy, `setOpacityRamp`) traktowane jako
    /// ATOMOWE — nigdy nie cięte (patrz `snapOverlayRange`, wołane PRZED tą
    /// funkcją gwarantuje że taka instrukcja jest albo w całości wewnątrz
    /// zakresu nakładki, albo w ogóle się nie przecina).
    private static func applyOverlay(
        to instructions: [AVMutableVideoCompositionInstruction],
        overlay: OverlayPlacement,
        placements: [ClipPlacement]
    ) -> [AVMutableVideoCompositionInstruction] {
        var result: [AVMutableVideoCompositionInstruction] = []

        for instruction in instructions {
            let overlapStart = max(instruction.timeRange.start, overlay.range.start)
            let overlapEnd = min(instruction.timeRange.end, overlay.range.end)
            guard overlapEnd > overlapStart else {
                result.append(instruction)
                continue
            }

            guard instruction.layerInstructions.count == 1 else {
                // Instrukcja przejścia — atomowa, nakładka doklejona NA WIERZCH
                // (pierwsza w tablicy = przód, ta sama konwencja co incoming/outgoing).
                let overlayLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: overlay.track)
                overlayLayer.setTransform(overlay.transform, at: instruction.timeRange.start)
                instruction.layerInstructions = [overlayLayer] + instruction.layerInstructions
                result.append(instruction)
                continue
            }

            guard let placement = placements.first(where: {
                $0.start <= instruction.timeRange.start && instruction.timeRange.end <= $0.start + $0.duration
            }) else {
                result.append(instruction)
                continue
            }

            let intersection = CMTimeRange(start: overlapStart, end: overlapEnd)
            let pieces = [
                CMTimeRange(start: instruction.timeRange.start, end: intersection.start),
                intersection,
                CMTimeRange(start: intersection.end, end: instruction.timeRange.end)
            ]
            for (index, piece) in pieces.enumerated() {
                guard piece.duration > .zero else { continue }
                let newInstruction = AVMutableVideoCompositionInstruction()
                newInstruction.timeRange = piece
                let mainLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: placement.track)
                mainLayer.setTransform(placement.transform, at: piece.start)
                if index == 1 {
                    let overlayLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: overlay.track)
                    overlayLayer.setTransform(overlay.transform, at: piece.start)
                    newInstruction.layerInstructions = [overlayLayer, mainLayer]
                } else {
                    newInstruction.layerInstructions = [mainLayer]
                }
                result.append(newInstruction)
            }
        }

        return result
    }

    /// Kolejność: realne wideo > wideo z Live Photo (jeśli włączony ruch) >
    /// wyrenderowane zdjęcie statyczne.
    /// Rozwiązuje źródła wszystkich elementów RÓWNOLEGLE (max 4 naraz —
    /// "worker pool" przez `TaskGroup`, nie bez limitu), zachowując
    /// przyporządkowanie po indeksie do dalszego, sekwencyjnego budowania
    /// kompozycji. Dla wideo/Live Photo to i tak niemal natychmiastowe
    /// (zwraca istniejący URL), ale dla zdjęć to pełne renderowanie —
    /// właśnie tu jest realny zysk.
    private static func resolveSourceURLs(
        for items: [MediaItem], canvasSize: CGSize, onProgress: ((Double) -> Void)? = nil
    ) async throws -> [Int: URL] {
        let maxConcurrent = 4
        var results: [Int: URL] = [:]
        var completedCount = 0
        let total = items.count
        try await withThrowingTaskGroup(of: (Int, URL?).self) { group in
            var nextIndex = 0
            func addNext() {
                guard nextIndex < items.count else { return }
                let index = nextIndex
                let item = items[index]
                nextIndex += 1
                group.addTask {
                    let url = try await resolveSourceURL(for: item, canvasSize: canvasSize)
                    return (index, url)
                }
            }
            for _ in 0..<min(maxConcurrent, items.count) { addNext() }
            while let (index, url) = try await group.next() {
                if let url { results[index] = url }
                completedCount += 1
                onProgress?(Double(completedCount) / Double(max(1, total)))
                addNext()
            }
        }
        return results
    }

    private static func resolveSourceURL(for item: MediaItem, canvasSize: CGSize) async throws -> URL? {
        if item.isVideo, let videoURL = item.videoURL {
            return videoURL
        }
        if item.isLivePhoto, item.useMotion, let pairedVideoURL = item.pairedVideoURL {
            return pairedVideoURL
        }
        if let thumbnail = item.thumbnail {
            let key = PhotoRenderCache.Key(
                assetIdentifier: item.pickerItemId ?? UUID().uuidString,
                duration: item.duration, width: Int(canvasSize.width), height: Int(canvasSize.height)
            )
            if let cached = await PhotoRenderCache.shared.cachedURL(for: key) {
                return cached
            }
            let rendered = try await ImageToVideoRenderer.render(image: thumbnail, duration: item.duration, size: canvasSize)
            await PhotoRenderCache.shared.store(rendered, for: key)
            return rendered
        }
        return nil
    }

    /// Ten sam wzorzec co `resolveSourceURL` (celowo zduplikowany, nie
    /// wydzielony do wspólnej funkcji nad `MediaItem`/`OverlayItem` — dopóki
    /// nie ma trzeciego realnego konsumenta, konkretna duplikacja jest tu
    /// bezpieczniejsza niż przedwczesna abstrakcja, patrz `Docs/Database.md`).
    /// Zdjęcia nakładki renderowane w PEŁNYM `canvasSize` (nie od razu w
    /// docelowym, małym rozmiarze pudełka PiP) — to samo źródło jakości co
    /// główny tor, skalowane w dół dopiero przez `overlayTransform`.
    private static func resolveOverlaySourceURL(for overlay: OverlayItem, canvasSize: CGSize) async throws -> URL? {
        if overlay.isVideo, let videoURL = overlay.videoURL {
            return videoURL
        }
        if overlay.isLivePhoto, overlay.useMotion, let pairedVideoURL = overlay.pairedVideoURL {
            return pairedVideoURL
        }
        if let thumbnail = overlay.thumbnail {
            let key = PhotoRenderCache.Key(
                assetIdentifier: overlay.pickerItemId ?? UUID().uuidString,
                duration: overlay.duration, width: Int(canvasSize.width), height: Int(canvasSize.height)
            )
            if let cached = await PhotoRenderCache.shared.cachedURL(for: key) {
                return cached
            }
            let rendered = try await ImageToVideoRenderer.render(image: thumbnail, duration: overlay.duration, size: canvasSize)
            await PhotoRenderCache.shared.store(rendered, for: key)
            return rendered
        }
        return nil
    }

    /// Głośność oryginalnego dźwięku ustawiana per-segment (`setVolume(_:at:)`
    /// obowiązuje od danego czasu aż do następnego wywołania), głośność
    /// muzyki jako jedna stała wartość na cały utwór. Dwa tory oryginalnego
    /// dźwięku (A/B) zamiast jednego — to samo naprzemienne rozłożenie co w
    /// `videoTrackA`/`videoTrackB`, potrzebne do crossfade.
    private static func buildAudioMix(
        originalAudioTrackA: AVMutableCompositionTrack?,
        originalAudioTrackB: AVMutableCompositionTrack?,
        originalVolumeSegments: [(trackIndex: Int, range: CMTimeRange, volume: Float)],
        musicTrack: AVMutableCompositionTrack?,
        musicVolume: Float
    ) -> AVMutableAudioMix? {
        var inputParameters: [AVMutableAudioMixInputParameters] = []

        if let originalAudioTrackA {
            let params = AVMutableAudioMixInputParameters(track: originalAudioTrackA)
            for segment in originalVolumeSegments where segment.trackIndex == 0 {
                params.setVolume(segment.volume, at: segment.range.start)
            }
            inputParameters.append(params)
        }
        if let originalAudioTrackB {
            let params = AVMutableAudioMixInputParameters(track: originalAudioTrackB)
            for segment in originalVolumeSegments where segment.trackIndex == 1 {
                params.setVolume(segment.volume, at: segment.range.start)
            }
            inputParameters.append(params)
        }

        if let musicTrack {
            let params = AVMutableAudioMixInputParameters(track: musicTrack)
            params.setVolume(musicVolume, at: .zero)

            // Delikatne "ducking" — muzyka w tle przycisza się (nie do zera)
            // dokładnie tam gdzie leci klip ze słyszalnym własnym dźwiękiem,
            // żeby jej nie zagłuszać, i wraca do normalnej głośności
            // pomiędzy takimi klipami. Sąsiadujące/nakładające się odcinki
            // scalone w jedno okno przed rampami, żeby dwie kolejne komendy
            // rampy nie kolidowały ze sobą przy klipach "na styk".
            let duckFactor: Float = 0.35
            let rampDuration = CMTime(seconds: 0.3, preferredTimescale: 600)
            let sortedAudibleRanges = originalVolumeSegments
                .filter { $0.volume > 0 }
                .map(\.range)
                .sorted { $0.start < $1.start }
            var duckRanges: [CMTimeRange] = []
            for range in sortedAudibleRanges {
                if let last = duckRanges.last, range.start <= last.end {
                    duckRanges[duckRanges.count - 1] = CMTimeRange(start: last.start, end: max(last.end, range.end))
                } else {
                    duckRanges.append(range)
                }
            }
            let duckedVolume = musicVolume * duckFactor
            for range in duckRanges {
                let fadeOutStart = max(.zero, range.start - rampDuration)
                params.setVolumeRamp(fromStartVolume: musicVolume, toEndVolume: duckedVolume, timeRange: CMTimeRange(start: fadeOutStart, duration: rampDuration))
                params.setVolumeRamp(fromStartVolume: duckedVolume, toEndVolume: musicVolume, timeRange: CMTimeRange(start: range.end, duration: rampDuration))
            }

            inputParameters.append(params)
        }

        guard !inputParameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        return audioMix
    }

    /// Buduje transform dla jednego segmentu: koryguje orientację źródła
    /// (`preferredTransform`), dokłada ręczny obrót usera (0/90/180/270),
    /// skaluje do `canvasSize` (fit = cała klatka widoczna, fill = wypełnia
    /// kadr, brzegi mogą być obcięte) i centruje.
    private static func layerTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        rotationDegrees: Int,
        cropFill: Bool,
        canvasSize: CGSize
    ) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))

        let extraRotation = extraRotationTransform(degrees: rotationDegrees, size: orientedSize)
        let rotatedSize: CGSize = (rotationDegrees == 90 || rotationDegrees == 270)
            ? CGSize(width: orientedSize.height, height: orientedSize.width)
            : orientedSize

        guard rotatedSize.width > 0, rotatedSize.height > 0 else { return preferredTransform }

        let scaleToFit = min(canvasSize.width / rotatedSize.width, canvasSize.height / rotatedSize.height)
        let scaleToFill = max(canvasSize.width / rotatedSize.width, canvasSize.height / rotatedSize.height)
        let scale = cropFill ? scaleToFill : scaleToFit

        let scaledWidth = rotatedSize.width * scale
        let scaledHeight = rotatedSize.height * scale
        let centerTransform = CGAffineTransform(
            translationX: (canvasSize.width - scaledWidth) / 2,
            y: (canvasSize.height - scaledHeight) / 2
        )

        return preferredTransform
            .concatenating(extraRotation)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(centerTransform)
    }

    /// Transform nakładki PiP — skaluje do małego "pudełka" w rogu kanwy i
    /// przesuwa na miejsce. `boxSize` to pomniejszona kopia `canvasSize` W
    /// TYCH SAMYCH PROPORCJACH (nie dowolny prostokąt) — dzięki temu
    /// `cropFill: true` na zdjęciu, które `ImageToVideoRenderer` już
    /// wyrenderował w proporcjach kanwy (fit + rozmyte tło), matematycznie
    /// NIGDY nic nie ucina (scale-to-fill == scale-to-fit przy tych samych
    /// proporcjach źródła i celu) — twarda zasada "nie przycinamy zdjęć"
    /// (`Docs/Studio.md`) zachowana automatycznie, bez specjalnego przypadku.
    /// Nakładki WIDEO o dowolnych proporcjach MOGĄ zostać przycięte — ten sam,
    /// już zaakceptowany kompromis co `cropFill` na głównym torze dla wideo.
    ///
    /// UWAGA: konwencja układu współrzędnych tu (translacja w przestrzeni
    /// pikseli surowego bufora wideo, top-left = (0,0), Y rośnie w dół — ta
    /// sama co istniejące `centerTransform` wyżej) jest INNA niż w
    /// `captionsAnimationTool` niżej (tam `CALayer` ma origin w lewym dolnym
    /// rogu). Zweryfikowane na realnym eksporcie w Fazie 1 build-order krok 2,
    /// nie założone na sucho.
    private static func overlayTransform(
        naturalSize: CGSize, preferredTransform: CGAffineTransform,
        corner: OverlayCorner, sizeScale: Double, canvasSize: CGSize
    ) -> CGAffineTransform {
        let boxSize = CGSize(
            width: canvasSize.width * sizeScale,
            height: canvasSize.width * sizeScale * (canvasSize.height / canvasSize.width)
        )
        let fillTransform = layerTransform(
            naturalSize: naturalSize, preferredTransform: preferredTransform,
            rotationDegrees: 0, cropFill: true, canvasSize: boxSize
        )
        let margin: CGFloat = canvasSize.width * 0.04
        let origin = cornerOrigin(corner, boxSize: boxSize, canvasSize: canvasSize, margin: margin)
        return fillTransform.concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    private static func cornerOrigin(_ corner: OverlayCorner, boxSize: CGSize, canvasSize: CGSize, margin: CGFloat) -> CGPoint {
        switch corner {
        case .topLeading:
            return CGPoint(x: margin, y: margin)
        case .topTrailing:
            return CGPoint(x: canvasSize.width - boxSize.width - margin, y: margin)
        case .bottomLeading:
            return CGPoint(x: margin, y: canvasSize.height - boxSize.height - margin)
        case .bottomTrailing:
            return CGPoint(x: canvasSize.width - boxSize.width - margin, y: canvasSize.height - boxSize.height - margin)
        }
    }

    /// Nakłada napisy jako `CATextLayer`e nad renderowanym wideo, przez
    /// `AVVideoCompositionCoreAnimationTool` (standardowy wzorzec AVFoundation
    /// do wypalania nakładek tekstowych w eksportowanym filmie — inny
    /// mechanizm niż transformy klipów, bo to dotyczy TREŚCI klatki, nie jej
    /// pozycji). Warstwy CALayer w tym kontekście mają origin w LEWYM DOLNYM
    /// rogu (ta sama konwencja co surowy `CGContext` gdzie indziej w tym
    /// projekcie), więc duże Y = bliżej góry ekranu.
    ///
    /// Karta outro PMemories (13.08.2026) KIEDYŚ też szła przez ten
    /// mechanizm (`outroStartTime` + dodatkowe warstwy) — 16.08.2026 wycofane
    /// po realnym przypadku cichej awarii SAMEJ nakładki tekstowej (tło się
    /// wyrenderowało, tekst nie), patrz `PMemoriesOutroCardRenderer`. Tekst
    /// outro jest teraz wypalony w pikselach tam, ta funkcja go już nie dotyczy.
    private static func animationTool(captions: [Caption], canvasSize: CGSize) -> AVVideoCompositionCoreAnimationTool {
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: canvasSize)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: canvasSize)
        parentLayer.addSublayer(videoLayer)

        let margin: CGFloat = 150
        let baseBoxHeight: CGFloat = 120
        let boxWidth = canvasSize.width - 80

        for caption in captions {
            let textLayer = CATextLayer()
            // Bez tła — kontur (ujemny `strokeWidth` = wypełnienie I obrys
            // naraz) i cień zamiast czarnego prostokąta za tekstem, żeby
            // napis "leżał" wprost na filmie ale został czytelny na jasnym/
            // ruchliwym tle (to samo podejście co TikTok/CapCut).
            //
            // ZNALEZIONY REALNY BUG 31.07.2026 (user: napis w ogóle się nie
            // pojawiał w eksporcie): `.font` w `NSAttributedString` jako
            // `UIFont` bywa PO CICHU ignorowane przez `CATextLayer` w
            // kontekście `AVVideoCompositionCoreAnimationTool` (znany,
            // udokumentowany problem CoreText/CATextLayer — nie wszędzie
            // akceptuje `UIFont`, potrzebuje `CTFont`). Naprawa: jawna
            // konwersja przez `CTFontCreateWithName`.
            let uiFont = UIFont(name: caption.font.rawValue, size: 48) ?? UIFont.boldSystemFont(ofSize: 48)
            let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: ctFont,
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -4
            ]
            let fullText = NSMutableAttributedString(string: caption.text, attributes: attributes)

            // "Share with Family" (TODO.md) — tłumaczenia dopisane pod
            // oryginałem, RAZEM w tym samym eksporcie (nie zamiana języka
            // appki). Mniejsza, systemowa czcionka (nie wybrany `caption.
            // font`) — dekoracyjne czcionki z `CaptionFont` nie mają
            // gwarantowanego kompletu glifów dla każdego skryptu (arabski,
            // hindi, tajski...), system zawsze ma poprawny fallback.
            let translationLines = caption.translations.keys.sorted().compactMap { caption.translations[$0] }
            if !translationLines.isEmpty {
                let translationFont = CTFontCreateWithName(UIFont.boldSystemFont(ofSize: 30).fontName as CFString, 30, nil)
                let translationAttributes: [NSAttributedString.Key: Any] = [
                    .font: translationFont,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .strokeColor: UIColor.black,
                    .strokeWidth: -4
                ]
                for line in translationLines {
                    fullText.append(NSAttributedString(string: "\n" + line, attributes: translationAttributes))
                }
            }

            textLayer.string = fullText
            textLayer.alignmentMode = .center
            textLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            textLayer.shadowOpacity = 0.6
            textLayer.shadowRadius = 4
            textLayer.shadowOffset = CGSize(width: 0, height: 2)
            textLayer.isWrapped = true
            textLayer.contentsScale = 2.0

            // Każda dodatkowa linia tłumaczenia dokłada miejsca w pionie,
            // żeby nic się nie ucinało — box rośnie w dół (od pozycji
            // kotwiczonej wg `caption.position`, patrz niżej).
            let boxHeight = baseBoxHeight + CGFloat(translationLines.count) * 40

            let y: CGFloat
            switch caption.position {
            case .top: y = canvasSize.height - margin - boxHeight
            case .center: y = (canvasSize.height - boxHeight) / 2
            case .bottom: y = margin
            }
            textLayer.frame = CGRect(x: (canvasSize.width - boxWidth) / 2, y: y, width: boxWidth, height: boxHeight)

            // Widoczny tylko w [startTime, endTime) — poza tym zakresem
            // przezroczysty. `AVCoreAnimationBeginTimeAtZero` synchronizuje
            // lokalny czas animacji z czasem kompozycji (sekundy od startu
            // filmu), tak jak wymaga tego `AVVideoCompositionCoreAnimationTool`.
            textLayer.opacity = 0
            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            visibility.values = [0, 1, 1, 0]
            visibility.keyTimes = [0, 0.001, 0.999, 1]
            visibility.duration = max(0.01, caption.endTime - caption.startTime)
            visibility.beginTime = AVCoreAnimationBeginTimeAtZero + caption.startTime
            visibility.isRemovedOnCompletion = false
            visibility.fillMode = .both
            textLayer.add(visibility, forKey: "captionVisibility")

            parentLayer.addSublayer(textLayer)
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }

    /// Obrót o 0/90/180/270 stopni wokół środka ramki źródła, z tą samą
    /// konwencją translacji-po-obrocie co standardowe `preferredTransform`
    /// wideo z telefonu (żeby wynik zostawał dodatnio pozycjonowany od 0,0).
    private static func extraRotationTransform(degrees: Int, size: CGSize) -> CGAffineTransform {
        switch degrees {
        case 90:
            return CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(translationX: size.height, y: 0))
        case 180:
            return CGAffineTransform(rotationAngle: .pi)
                .concatenating(CGAffineTransform(translationX: size.width, y: size.height))
        case 270:
            return CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(translationX: 0, y: size.width))
        default:
            return .identity
        }
    }
}
