import SwiftUI
import UIKit

/// Krótka branded scena doklejana na końcu KAŻDEGO eksportowanego Memory
/// (12/13.08.2026). ŚWIADOMIE bez żadnych statystyk podróży — user wprost:
/// "PMemories ma być narzędziem do tworzenia DOWOLNYCH wspomnień, nie tylko
/// podróży" (stąd też wcześniejsza, osobna karta "Travel Replay" CAŁKOWICIE
/// USUNIĘTA, patrz `HISTORIA.md` 13.08.2026).
///
/// **16.08.2026 — tekst PRZENIESIONY z powrotem do pikseli.** Wersja z
/// 13.08.2026 trzymała JEDEN ciągły klip tła i animowała tekst NAD nim przez
/// `CATextLayer`/`AVVideoCompositionCoreAnimationTool` (ten sam mechanizm co
/// napisy). Realny przypadek (narzeczona usera): pierwszy eksport miał
/// poprawną końcówkę (tło + tekst), po edycji tego samego projektu drugi
/// eksport miał TŁO ale bez tekstu — sam klip się renderował poprawnie,
/// zawiodła wyłącznie warstwa nakładki tekstowej. To DRUGI raz gdy dokładnie
/// ten mechanizm zawodzi po cichu dla tej karty (pierwszy raz: 15.08.2026,
/// cały klip potrafił się nie wyrenderować). Zamiast dalej łatać zawodny
/// mechanizm nakładki w momencie eksportu, tekst każdej fazy jest teraz
/// WYPALONY w pikselach przez `ImageRenderer` (dokładnie ten sam, sprawdzony
/// mechanizm co samo tło) — zero zależności od `CATextLayer` w tej karcie.
/// Dwie fazy = DWA krótkie klipy renderowane osobno, złączone standardowym
/// `.crossfade` z `VideoComposer` (płynne przenikanie, nie twarde cięcie) —
/// wizualnie nadal JEDNA scena, bo tło jest IDENTYCZNE w obu fazach (przenika
/// się samo w sobie, widać tylko zmianę tekstu), więc user'owe "jeden ciągły
/// ekran, nie sklejone slajdy" zostaje spełnione bez ryzykownej nakładki.
private struct PMemoriesOutroPhaseView: View {
    let size: CGSize
    let phaseIndex: Int

    var body: some View {
        ZStack {
            Palette.heroGradient
            content
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var content: some View {
        if phaseIndex == 0 {
            VStack(spacing: 18) {
                Text("✨").font(.system(size: 50))
                Text("PMemories").font(.system(size: 108, weight: .bold)).foregroundStyle(.white)
                Text(L("Turn your memories into stories."))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
        } else {
            Text(L("Coming soon"))
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

enum PMemoriesOutroCardRenderer {
    /// Dwa stany po ~2.2s (user: "PMemories+tagline ~2s, Coming soon ~2s",
    /// łącznie "4-5 sekund") — `duration` = suma obu (zachowane do UI/
    /// dokumentacji, sam `VideoComposer` liczy długość klipów z `phaseCount`).
    static let phaseDuration: Double = 2.2
    static let phaseCount = 2
    static let duration: Double = phaseDuration * Double(phaseCount)

    @MainActor
    private static func renderPhaseImage(size: CGSize, phaseIndex: Int) -> UIImage? {
        let renderer = ImageRenderer(content: PMemoriesOutroPhaseView(size: size, phaseIndex: phaseIndex))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    /// Renderuje obie fazy jako osobne klipy wideo, z JEDNĄ próbą ponowienia
    /// na fazę (15.08.2026 — realny przypadek chwilowej awarii renderowania
    /// bez żadnego zgłoszonego błędu). Zwraca tyle URL-i ile faz się udało
    /// wyrenderować — `EditView` dokleja WSZYSTKIE zwrócone jako sekwencję
    /// klipów; jeśli któraś faza zawiedzie po obu próbach, reszta i tak
    /// trafia do eksportu zamiast tracić całą kartę.
    static func renderOutroClips(size: CGSize) async -> [URL] {
        var urls: [URL] = []
        for phaseIndex in 0..<phaseCount {
            var clipURL: URL?
            for attempt in 1...2 {
                guard let image = await renderPhaseImage(size: size, phaseIndex: phaseIndex) else {
                    print("⚠️ PMemories outro: renderPhaseImage(\(phaseIndex)) zwróciło nil (próba \(attempt)/2)")
                    continue
                }
                do {
                    clipURL = try await ImageToVideoRenderer.render(image: image, duration: phaseDuration, size: size)
                    break
                } catch {
                    print("⚠️ PMemories outro: ImageToVideoRenderer.render(\(phaseIndex)) rzuciło błąd (próba \(attempt)/2): \(error)")
                }
            }
            if let clipURL {
                urls.append(clipURL)
            } else {
                print("⚠️ PMemories outro: faza \(phaseIndex) nie wyrenderowała się po 2 próbach — pomijam")
            }
        }
        return urls
    }
}
