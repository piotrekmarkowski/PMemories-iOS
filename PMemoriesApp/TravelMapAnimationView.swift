import SwiftUI
import MapKit
import UIKit

/// Animowana trasa podróży na satelitarnym globusie.
///
/// **31.07.2026 — podgląd przeszedł na żywą, płynną `MKMapView`
/// (`TravelLiveMapView`), naprawiając znane klatkowanie.** Wcześniej (od
/// 30.07.2026) ten widok dzielił DOSŁOWNIE jeden silnik z eksportem wideo
/// (`TravelMapVideoRenderer.renderFrames`) — dyskretne "zdjęcia" ukrytej
/// mapy klatka po klatce, gwarancja 100% zgodności z eksportem kosztem
/// płynności (kamera skakała zamiast płynnie jechać). Eksport TEGO NIE
/// POTRZEBUJE (nie ogląda się w czasie rzeczywistym renderowania), więc
/// zostaje bez zmian przy starym silniku. Podgląd dostał osobny,
/// NATYWNIE animowany silnik (`setCamera`/`UIView.animate`) — zero rozjazdu
/// mimo dwóch implementacji, bo obie nadal karmią się TYMI SAMYMI
/// wartościami z `TravelCinematics`/`RouteProvider`/`VehicleIconSet`, patrz
/// komentarz w `TravelLiveMapView.swift`.
struct TravelMapAnimationView: View {
    let stops: [TripStop]
    var speedMultiplier: Double = 1.0
    var mapTheme: MapTheme = .satellite

    @State private var runToken = UUID()
    @State private var distanceKm: Double = 0
    @State private var isAnimationFinished = false
    @State private var isSaving = false
    @State private var saveProgress: Double = 0
    @State private var didSaveSucceed = false
    @State private var saveError: String?
    @State private var playbackError: String?

    // "Cinematic Lighting" Faza 1 (`Travel.md`, 30.07.2026) — kolorowy tint
    // NAD żywą mapą. Od 31.07.2026 karmiony REALNYM postępem z
    // `TravelLiveMapView` (nie przybliżeniem z liczby wyświetlonych klatek
    // jak w starej, buforowanej wersji podglądu) — poprawa "za darmo" przy
    // okazji przejścia na żywą kamerę.
    @State private var currentTint: LightingCondition = .day
    @State private var nextTint: LightingCondition = .day
    @State private var tintBlend: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TravelLiveMapView(
                stops: stops, speedMultiplier: speedMultiplier, mapTheme: mapTheme, runToken: runToken,
                isPaused: isSaving,
                onDistanceUpdate: { distanceKm = $0 },
                onLightingUpdate: { current, next, blend in
                    currentTint = current
                    nextTint = next
                    tintBlend = blend
                },
                onFinished: { withAnimation { isAnimationFinished = true } },
                onError: { playbackError = $0 }
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay(
                ZStack {
                    currentTint.tintColor.opacity(currentTint.tintOpacity * (1 - tintBlend))
                    nextTint.tintColor.opacity(nextTint.tintOpacity * tintBlend)
                }
                .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) { distanceBadge }

            VStack(spacing: 12) {
                if isAnimationFinished {
                    Button {
                        replayAnimation()
                    } label: {
                        Label("Play Again", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.blue)
                    .transition(.opacity)
                }

                // Zwykły `.borderedProminent` + statyczny napis "Zapisywanie…"
                // dawał zero informacji zwrotnej podczas długiego renderowania
                // — user: "wygląda jakby coś się zawiesiło". Własny wygląd
                // przycisku (zamiast stylu systemowego, który narzuca swoje
                // tło i ukryłby nasz pasek) z paskiem wypełniającym się wraz
                // z realnym postępem (`saveProgress`, liczony z faktycznej
                // liczby zapisanych klatek w `TravelMapVideoRenderer`, nie
                // szacowany czasowo).
                Button {
                    Task { await saveVideo() }
                } label: {
                    ZStack(alignment: .leading) {
                        Palette.accent
                        if isSaving {
                            // Bardziej wyraźny pasek postępu (10.08.2026,
                            // user: "pasek download z mapy musi być bardziej
                            // wyraźny") — 0.28 białego na pomarańczowym
                            // `Palette.accent` dawało prawie niewidoczny
                            // kontrast. Wyższa nieprzezroczystość + jasna
                            // krawędź na końcu wypełnienia, żeby pasek był
                            // czytelny na pierwszy rzut oka, nie tylko po
                            // dokładnym wpatrzeniu się.
                            GeometryReader { geo in
                                let fillWidth = geo.size.width * saveProgress
                                ZStack(alignment: .trailing) {
                                    Color.white.opacity(0.55)
                                    Rectangle()
                                        .fill(.white)
                                        .frame(width: 3)
                                }
                                .frame(width: fillWidth)
                            }
                        }
                        HStack {
                            Spacer()
                            if isSaving {
                                Label("\(L("Saving…")) \(Int(saveProgress * 100))%", systemImage: "square.and.arrow.down")
                            } else {
                                Label("Save as Video", systemImage: "square.and.arrow.down")
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .font(.headline)
                    }
                    // `Capsule()` bez ograniczenia rozmiaru rozciąga się na
                    // całą dostępną przestrzeń (user: screenshot z przyciskiem
                    // na cały ekran) — poprzednio `.buttonStyle(.borderedProminent)`
                    // sam narzucał rozsądny rozmiar, ale musieliśmy z niego
                    // zrezygnować (własne tło paska postępu). Jawna wysokość
                    // zamiast tego — zmniejszona z 52 do 46 (user: "przycisk
                    // jest za duży").
                    .frame(height: 46)
                    // Pasek wypełnienia był OSOBNĄ `Capsule()` — jej promień
                    // zaokrąglenia liczy się z WŁASNEJ (wąskiej!) szerokości,
                    // więc przy niskim procencie miał INNY promień niż
                    // zewnętrzna kapsuła i wizualnie "nie pokrywał się" z
                    // przyciskiem (user, ekran startowy paska). Fix: zwykły
                    // prostokątny kolor + PRZYCIĘCIE całości do jednej,
                    // wspólnej `Capsule()` na samym końcu — promień liczony
                    // raz, z pełnego rozmiaru przycisku, więc lewa krawędź
                    // paska zawsze pasuje do zaokrąglenia tła.
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                // NIE `.disabled(isSaving)` (10.08.2026) — user zgłosił że
                // pasek postępu dalej wygląda blado mimo podbicia opacity
                // wypełnienia wyżej. Prawdziwa przyczyna: SwiftUI automatycznie
                // przyciemnia CAŁĄ zawartość `Button`a gdy jest `.disabled()`,
                // nawet z `.buttonStyle(.plain)` i czysto własną zawartością
                // (`Palette.accent`, `Label`) — efekt widoczny jako "mapa
                // przeświecająca przez pasek", nie tylko sam pasek postępu.
                // `.allowsHitTesting` blokuje dotknięcia (ten sam cel co
                // `.disabled`) BEZ dotykania `\.isEnabled`, więc bez
                // przyciemnienia.
                .allowsHitTesting(!isSaving)

                // Szacowany czas PRZED startem (03.08.2026, user: eksport
                // potrafi trwać kilka-kilkanaście minut przy trasach z
                // wieloma środkami transportu — appka ma o tym uczciwie
                // uprzedzić, zamiast zaskakiwać milczącym paskiem postępu).
                // Liczba ze STAŁEJ zmierzonej na urządzeniu (`~0.4s/klatka`,
                // `TravelMapVideoRenderer` profiler, 03.08.2026), NIE
                // zgadywana z powietrza — ale to wciąż tylko ORIENTACYJNE
                // oszacowanie (realny czas zależy od sieci/liczby kafelków),
                // stąd "ok." w tekście zamiast twardej liczby.
                if !isSaving {
                    Text("Export can take a while (est. ~\(estimatedExportMinutesText)) — we're working on making it faster 🙂")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer().frame(height: 12)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Travel Map")
        .navigationBarTitleDisplayMode(.inline)
        // BUG znaleziony 01.08.2026 (user: "dalej szare ekrany przy
        // podglądzie jak oddala mapę... wystarczy że zacznie pobierać
        // obszar z którego zaczynamy trasę zaraz po wyborze") — prefetch
        // pierwszego odcinka wewnątrz `TravelLiveMapView.runAnimation`
        // zaczynał się DOPIERO po ustawieniu i potwierdzeniu szerokiego
        // widoku bezpieczeństwa — mało czasu z wyprzedzeniem. Ten `.task`
        // startuje w tle NATYCHMIAST gdy ekran się pojawia (fire-and-forget,
        // nie blokuje niczego — patrz `feedback_pmemories...`: user
        // odrzucił wcześniej blokujący ekran ładowania), więc kafelki mają
        // maksymalny możliwy czas na doładowanie się PRZED jakąkolwiek
        // animacją. Dla lotów prefetchujemy ŚRODEK CAŁEGO odcinka (nie sam
        // punkt startu) — establishing shot dla lotów centruje się właśnie
        // tam (patrz `RouteProvider.midpoint`/`TravelLiveMapView`), nie na
        // samym lotnisku startowym.
        .task {
            guard let firstCoordinate = stops.first?.coordinate else { return }
            let prefetchCenter: CLLocationCoordinate2D
            if stops.count > 1, stops[1].transport == .plane, let secondCoordinate = stops[1].coordinate {
                prefetchCenter = RouteProvider.midpoint(from: firstCoordinate, to: secondCoordinate)
            } else {
                prefetchCenter = firstCoordinate
            }
            MapTilePrefetcher.prefetch(coordinate: prefetchCenter, mapTheme: mapTheme)
        }
        // Profil wydajności/debug kamery (01.08.2026) USUNIĘTE z alertu
        // (01.08.2026, po potwierdzeniu naprawy: 286 klatek/8.8s, zero
        // awarii) — user: "te informacje... zwykli userzy nie będą ich
        // widzieć?" — TAK, widzieliby, bo alert jest wspólny dla
        // wszystkich. Diagnostyka spełniła swoją rolę (znalezienie buga z
        // Jetsam), dane wciąż trafiają do konsoli Xcode
        // (`TravelMapVideoRenderer.printProfile`) na potrzeby przyszłego
        // dostrajania, po prostu nie pokazują się już zwykłemu userowi.
        .alert("Saved to camera roll", isPresented: $didSaveSucceed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your travel video has been saved to your camera roll.")
        }
        .alert("Save failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Try Again") {
                Task { await saveVideo() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert("Preview playback failed", isPresented: .init(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    private func saveVideo() async {
        isSaving = true
        saveProgress = 0
        defer { isSaving = false }

        // Patrz `EditView.performExport` (HISTORIA) po pełne uzasadnienie —
        // eksport mapy potrafi trwać podobnie długo (200+ przechwyceń
        // klatek), więc ten sam problem automatycznego blokowania ekranu
        // dotyczy i tutaj.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 31.07.2026 — mapa NIE miała jeszcze `beginBackgroundTask` (miał
        // go tylko eksport filmu w Studio), więc zejście z ekranu podczas
        // zapisywania trasy ucinało renderowanie dużo szybciej niż w
        // Studio. Ten sam wzorzec + powiadomienie po zakończeniu (user:
        // "żeby można było robić coś innego i tylko dostać komunikat") —
        // patrz `ExportNotifier` po uczciwe zastrzeżenie o limitach iOS.
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PMemories Travel Map Export") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        defer { UIApplication.shared.endBackgroundTask(backgroundTaskID) }
        ExportNotifier.requestAuthorizationIfNeeded()

        do {
            try await TravelMapVideoRenderer.renderAndSave(
                stops: stops, speedMultiplier: speedMultiplier, mapTheme: mapTheme,
                onProgress: { progress in saveProgress = progress }
            )
            didSaveSucceed = true
            ExportNotifier.notify(title: L("Your travel video is ready!"), body: L("Saved to your camera roll."))
        } catch {
            saveError = error.localizedDescription
            ExportNotifier.notify(title: L("Export failed"), body: error.localizedDescription)
        }
    }

    /// Resetuje podgląd i puszcza go od nowa — wywoływane z przycisku
    /// "Odtwórz ponownie", który pojawia się dopiero po zakończeniu
    /// pierwszego przejazdu. Nowy `runToken` = `TravelLiveMapView.updateUIView`
    /// wykrywa zmianę i restartuje koordynatora od zera.
    private func replayAnimation() {
        isAnimationFinished = false
        distanceKm = 0
        runToken = UUID()
    }

    /// Orientacyjny czas eksportu (03.08.2026) — patrz komentarz przy
    /// przycisku "Save as Video". Stała `secondsPerFrame` to średnia
    /// zmierzona bezpośrednio na urządzeniu (`TravelMapVideoRenderer`
    /// profiler, kilka realnych eksportów tego samego dnia: 367-607ms/
    /// klatkę, zależnie od sieci) — CELOWO ta sama liczba niezależnie od
    /// `mapTheme`, bo Minimal White nie było jeszcze zmierzone na
    /// urządzeniu (lepiej ostrożnie zawyżone oszacowanie niż zgadywanie
    /// liczby bez pokrycia w pomiarach).
    private var estimatedExportSeconds: Double {
        guard stops.count >= 2 else { return 0 }
        let legs = Double(stops.count - 1)
        let stepsPerLeg = Double(max(8, Int(261.0 / max(1.0, speedMultiplier))))
        let framesPerLeg = stepsPerLeg + 1
        let secondsPerFrame = 0.4
        return legs * framesPerLeg * secondsPerFrame
    }

    private var estimatedExportMinutesText: String {
        let minutes = max(1, Int((estimatedExportSeconds / 60).rounded(.up)))
        return minutes == 1 ? "1 \(L("min"))" : "\(minutes) \(L("min"))"
    }

    private var distanceBadge: some View {
        Text(String(format: "%.0f km", distanceKm))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.top, 50)
            .padding(.trailing, 24)
    }

}
