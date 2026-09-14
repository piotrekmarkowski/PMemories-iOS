import SwiftUI
import AVFoundation
import UIKit

/// Wybór punktu początku/końca klipu wideo (Live Photo z ruchem albo
/// realnego wideo) w obrębie źródłowego pliku — pierwsza funkcja modułu
/// Studio (`Docs/Studio.md`). Dotyka bezpośrednio `item.trimStart`/
/// `item.duration`, oznacza `isManuallyTrimmed`, żeby automatyczne
/// rozłożenie czasu po zmianie utworu tego nie nadpisało.
struct TrimView: View {
    @Binding var item: MediaItem
    /// Jeśli podane, pokazuje sekcję "Podziel klip" — wywoływane z punktem
    /// podziału (sekundy w źródle), `EditView` zamienia jeden element w
    /// timeline na dwa niezależnie przycięte kawałki tego samego źródła.
    var onSplit: ((Double) -> Void)?
    /// Pierwszy element sekwencji nie ma przejścia PRZED sobą (nic przed
    /// nim nie ma) — ukrywa `transitionPicker`, ten sam wzorzec co
    /// `TravelMapView.StopRow` ukrywające "Dotarłeś" dla pierwszego przystanku.
    var isFirst: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var splitPoint: Double

    init(item: Binding<MediaItem>, isFirst: Bool = false, onSplit: ((Double) -> Void)? = nil) {
        self._item = item
        self.isFirst = isFirst
        self.onSplit = onSplit
        let start = item.wrappedValue.trimStart
        let end = start + item.wrappedValue.duration
        self._splitPoint = State(initialValue: (start + end) / 2)
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Text("Edit Clip")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            if let sourceDuration = item.sourceDuration, sourceDuration > 0 {
                VStack(spacing: 12) {
                    TrimRangeSlider(
                        sourceURL: item.videoURL ?? item.pairedVideoURL,
                        sourceDuration: sourceDuration,
                        trimStart: $item.trimStart,
                        selectedDuration: $item.duration,
                        onEdited: { item.isManuallyTrimmed = true }
                    )
                    .padding(.horizontal, 24)

                    Text("\(format(item.trimStart)) – \(format(item.trimStart + item.duration))  •  \(format(item.duration)) \(L("of")) \(format(sourceDuration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if item.isManuallyTrimmed {
                    Button("Restore automatic timing") {
                        item.isManuallyTrimmed = false
                        item.trimStart = 0
                    }
                    .font(.caption)
                }

                speedPicker

                volumePicker

                rotateAndCropControls

                if !isFirst {
                    transitionPicker
                }

                if let onSplit {
                    VStack(spacing: 8) {
                        Divider()
                        Slider(value: $splitPoint, in: item.trimStart...(item.trimStart + item.duration))
                        Button("\(L("Split clip here")) (\(format(splitPoint)))", systemImage: "scissors") {
                            onSplit(splitPoint)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)
                }
            } else {
                Text("Source clip length unavailable")
                    .foregroundStyle(.secondary)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height((onSplit != nil ? 640 : 540) + (isFirst ? 0 : 90) + 190)])
    }

    /// Głośność oryginalnego dźwięku TEGO klipu — osobna od głośności
    /// muzyki w tle (`EditView.musicVolume`), część "Miksowania audio"
    /// z `Docs/Studio.md`.
    private var volumePicker: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $item.originalVolume, in: 0...1)
                Text("\(Int(item.originalVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Obrót (cykl 0→90→180→270→0) i tryb kadrowania (fit/fill) — ostatnie
    /// dwie z pierwotnej piątki funkcji Studio (Trim/Split/Crop/Rotate/Speed).
    /// Zastosowane realnie w `VideoComposer` przez `AVMutableVideoComposition`,
    /// nie tylko kosmetyka UI.
    private var rotateAndCropControls: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 24) {
                Button {
                    item.rotationDegrees = (item.rotationDegrees + 90) % 360
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                        .font(.caption)
                }

                Picker("Crop mode", selection: $item.cropFill) {
                    Text("Fit").tag(false)
                    Text("Fill").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Prędkość odtwarzania — presety zamiast dowolnego suwaka, bo user
    /// zwykle chce jednego z kilku znanych efektów (slow-mo, 2x itd.), nie
    /// precyzyjnej wartości pośredniej.
    private var speedPicker: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Speed")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { speed in
                    Button {
                        item.speed = speed
                    } label: {
                        Text(speedLabel(speed))
                            .font(.caption.weight(item.speed == speed ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                item.speed == speed ? Palette.blue.opacity(0.2) : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    /// Styl przejścia PRZED tym klipem — "Auto" (`item.transitionStyle ==
    /// nil`) zostawia dobór appce (`TransitionStyle.auto`), reszta to ręczny
    /// override. Ten sam wzorzec Capsule-buttons co `speedPicker` wyżej.
    private var transitionPicker: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Transition")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                transitionButton(label: L("Auto"), isSelected: item.transitionStyle == nil) {
                    item.transitionStyle = nil
                }
                // Premium style (`.isPremium`) pominięte tu dla zwykłych
                // userów — ten kompaktowy picker to szybki ręczny override,
                // zablokowana (kłódka) prezentacja żyje w `StyleView`. Founder
                // (30.08.2026, `TesterRegistry.hasPremiumUnlocked`) widzi je
                // też tutaj.
                ForEach(TransitionStyle.allCases.filter { !$0.isPremium || TesterRegistry.hasPremiumUnlocked(AuthManager.shared.userIdentifier) }) { style in
                    transitionButton(label: style.label, isSelected: item.transitionStyle == style) {
                        item.transitionStyle = style
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func transitionButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .bold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.blue.opacity(0.2) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == 1.0 ? "1x" : String(format: "%.1fx", speed)
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}

/// Prosty suwak z dwoma uchwytami (start/koniec) — nie ma gotowego
/// dual-handle range slidera w SwiftUI, więc zrobiony ręcznie przez
/// DragGesture na dwóch uchwytach nad wspólnym paskiem. Nad suwakiem —
/// prawdziwy odtwarzacz (`AVPlayer`), nie tylko statyczna klatka (user
/// 31.07.2026: pierwsza wersja z samą klatką "nie bardzo widzę co się
/// dzieje na filmiku") — seek na żywo podczas przeciągania uchwytów POKAZUJE
/// klatkę w miejscu przeciągania (jak wcześniej), ale dodatkowo przycisk Play
/// odtwarza faktyczny wybrany fragment (dźwięk + ruch), zatrzymuje się
/// automatycznie na końcu zaznaczenia (`addBoundaryTimeObserver`).
private struct TrimRangeSlider: View {
    let sourceURL: URL?
    let sourceDuration: Double
    @Binding var trimStart: Double
    @Binding var selectedDuration: Double
    let onEdited: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var boundaryObserver: Any?

    private let trackHeight: CGFloat = 44
    private let handleWidth: CGFloat = 18
    private let minSelectionSeconds: Double = 0.3

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                if let player {
                    TrimPlayerLayerView(player: player)
                }
                // Mały play w rogu, nie duży na środku — user 31.07.2026:
                // "wiem że to jest wideo, dobrze by było widzieć cały czysty
                // ekran" — duży przycisk zasłaniał kadr, który właśnie miał
                // być widoczny.
                if !isPlaying {
                    Button(action: playSelection) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            GeometryReader { geo in
                let width = geo.size.width
                let startFraction = trimStart / sourceDuration
                let endFraction = (trimStart + selectedDuration) / sourceDuration
                let startX = CGFloat(startFraction) * width
                let endX = CGFloat(endFraction) * width
                // 30.08.2026 — realny bug: uchwyt to `Capsule` szerokości
                // `handleWidth` WYŚRODKOWANA na `startX`/`endX` (`.position(x:)`
                // ustawia ŚRODEK, nie krawędź). Dla nietkniętego klipu
                // `trimStart == 0` → `startX == 0` → połowa uchwytu (9pt)
                // renderuje się poza lewą krawędzią paska, niewidoczna i
                // nie do złapania — user: "dlaczego poczatku filmiku nie
                // moge przesunac". Ten sam problem symetrycznie po prawej,
                // gdy `endX` blisko `width` (klip nieprzycięty na końcu).
                // Naprawione: SAMA WIDOCZNA/ŁAPALNA pozycja uchwytu wcięta o
                // pół jego szerokości od krawędzi paska — logika przeciągania
                // (`value.location.x` względem `width` paska, NIE względem
                // pozycji spoczynkowej uchwytu) zostaje bez zmian, więc
                // przesunięcie do samego zera dalej działa poprawnie, tylko
                // uchwyt startowy zawsze zostaje w pełni widoczny i chwytny.
                let handleHalfWidth = handleWidth / 2
                let displayStartX = min(max(startX, handleHalfWidth), width - handleHalfWidth)
                let displayEndX = min(max(endX, handleHalfWidth), width - handleHalfWidth)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.blue.opacity(0.35))
                        .frame(width: max(0, endX - startX))
                        .offset(x: startX)

                    handle
                        .position(x: displayStartX, y: trackHeight / 2)
                        .gesture(DragGesture().onChanged { value in
                            stopPlayback()
                            let minGapX = CGFloat(minSelectionSeconds / sourceDuration) * width
                            let clampedX = min(max(0, value.location.x), endX - minGapX)
                            let newStart = Double(clampedX / width) * sourceDuration
                            let delta = newStart - trimStart
                            trimStart = newStart
                            selectedDuration -= delta
                            onEdited()
                            seek(to: newStart)
                        })

                    handle
                        .position(x: displayEndX, y: trackHeight / 2)
                        .gesture(DragGesture().onChanged { value in
                            stopPlayback()
                            let minGapX = CGFloat(minSelectionSeconds / sourceDuration) * width
                            let clampedX = max(min(value.location.x, width), startX + minGapX)
                            let newEnd = Double(clampedX / width) * sourceDuration
                            selectedDuration = newEnd - trimStart
                            onEdited()
                            seek(to: newEnd)
                        })
                }
                .frame(height: trackHeight)
            }
            .frame(height: trackHeight)
        }
        .task {
            guard let sourceURL else { return }
            let newPlayer = AVPlayer(url: sourceURL)
            player = newPlayer
            seek(to: trimStart)
        }
        .onDisappear { stopPlayback() }
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playSelection() {
        guard let player else { return }
        seek(to: trimStart)
        isPlaying = true
        player.play()
        let endTime = CMTime(seconds: trimStart + selectedDuration, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) {
            player.pause()
            isPlaying = false
        }
    }

    private func stopPlayback() {
        guard isPlaying, let player else { return }
        player.pause()
        isPlaying = false
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Palette.blue)
            .frame(width: handleWidth, height: trackHeight)
            .shadow(radius: 2)
    }
}

/// Cienki `UIViewRepresentable` wokół `AVPlayerLayer` — `VideoPlayer` z AVKit
/// dokłada własne kontrolki odtwarzania (scrubber, play/pause), których tu
/// NIE chcemy (mamy własny suwak Trim i własny przycisk Play).
private struct TrimPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
