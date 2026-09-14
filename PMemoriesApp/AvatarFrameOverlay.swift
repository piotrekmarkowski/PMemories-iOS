import SwiftUI

/// Warstwowa "szklana" ramka awatara — czysto programowa w SwiftUI
/// (30.08.2026, po trzech nieudanych próbach wycinania gotowych PNG z
/// obrazków referencyjnych usera — za każdym razem jakiś fragment
/// wychodził źle wycięty: białe plamy, ucięta ikonka, poświata sięgająca
/// za daleko). User dał precyzyjną specyfikację proporcji zamiast kolejnej
/// grafiki do cięcia — zero rastrowych assetów eliminuje całą tę klasę
/// błędów raz na zawsze, bo nic nie jest wycinane z zewnętrznego obrazka.
///
/// Proporcje relatywne do `avatarSize` (nie stałe punkty), żeby wyglądało
/// identycznie w 30pt/68pt/84pt zamiast osobnego strojenia w trzech
/// miejscach:
/// - grubość pierścienia: 3.2% średnicy zdjęcia
/// - średnica odznaki: 38.5% średnicy zdjęcia
/// - przesunięcie środka odznaki: 33.2% średnicy w obu osiach (róg ~4-5
///   godziny na tarczy zegara)
/// Świadomie BEZ iskierki — user: "nie dodawałbym sparkle w ogóle...
/// ramka będzie znacznie bardziej uniwersalna, nie będzie wyglądała jak
/// achievement sticker".
struct AvatarFrameOverlay: View {
    let color: Color
    let iconName: String
    let avatarSize: CGFloat

    var body: some View {
        ring
            .overlay(badge)
    }

    /// `AngularGradient` zamiast płaskiego koloru — daje efekt "szklanej
    /// rurki" (jasny odblask w jednym miejscu, ciemniejsze partie gdzie
    /// indziej) zamiast płaskiego, matowego paska koloru.
    private var ring: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        color, color.opacity(0.75), Color.white.opacity(0.95),
                        color.opacity(0.85), color, color.opacity(0.6), color,
                    ],
                    center: .center
                ),
                lineWidth: avatarSize * 0.032
            )
            .frame(width: avatarSize, height: avatarSize)
            .shadow(color: color.opacity(0.45), radius: avatarSize * 0.07)
    }

    private var badge: some View {
        let diameter = avatarSize * 0.385
        let offset = avatarSize * 0.332
        return Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
            .overlay(
                // 0.48→0.40 (30.08.2026, user: "delikatnie pomniejszyć
                // samą koronę") — mniejsza ikona względem koła odznaki,
                // więcej marginesu dookoła.
                Image(systemName: iconName)
                    .font(.system(size: diameter * 0.40, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(0.5), radius: avatarSize * 0.05)
            .offset(x: offset, y: offset)
    }
}

/// Wybiera właściwy sposób narysowania ramki dla dowolnego `AvatarFrame` —
/// gotowy obrazek (`assetName`, tylko sezonowe ramki, tylko `#if DEBUG`)
/// albo programowa `AvatarFrameOverlay` (`color`/`iconName`, cała reszta
/// katalogu). Jedno miejsce zamiast powtarzania tego samego rozgałęzienia
/// w `ProfileView`/`HomeView`/`AvatarFrameView` (30.08.2026).
struct AvatarFrameBadge: View {
    let frame: AvatarFrame
    let avatarSize: CGFloat

    var body: some View {
        #if DEBUG
        if frame.maskAssetName != nil, let assetName = frame.assetName {
            // Druga generacja `PremiumBadge*` (05.09.2026) — pierścień
            // renderowany na `avatarSize * outerScale`, WYŚRODKOWANY z
            // powrotem w `avatarSize` (06.09.2026, user: zmierzył na
            // realnym zrzucie, że Premium wygląda ~15-20% mniej niż Free —
            // przyczyna: naturalny przezroczysty margines wokół dekoracji w
            // PNG, którego darmowe, wektorowo rysowane ramki w ogóle nie
            // mają). Zdjęcie jest przycinane osobno (`.mask()`, patrz
            // `avatarFramedPhoto(...)` w tym samym pliku) TĄ SAMĄ maską i
            // TYM SAMYM `outerScale`, więc oba obrazy dalej dzielą
            // identyczny układ współrzędnych.
            Image(assetName)
                .resizable()
                .frame(width: avatarSize * frame.outerScale, height: avatarSize * frame.outerScale)
                .frame(width: avatarSize, height: avatarSize)
        } else if let assetName = frame.assetName {
            Image(assetName)
                .resizable()
                .frame(width: avatarSize * frame.overlayScaleFactor, height: avatarSize * frame.overlayScaleFactor)
        } else if let iconName = frame.iconName {
            AvatarFrameOverlay(color: frame.color, iconName: iconName, avatarSize: avatarSize)
        }
        #else
        if let iconName = frame.iconName {
            AvatarFrameOverlay(color: frame.color, iconName: iconName, avatarSize: avatarSize)
        }
        #endif
    }
}

extension View {
    /// Dopasowuje i przycina zdjęcie do PRAWDZIWEGO otworu danej ramki
    /// (06.09.2026, user: prawdziwe zdjęcie testowe pokazało uciętą głowę
    /// na wszystkich ramkach Premium — przyczyna: `self` było dopasowywane
    /// `aspectRatio(.fill)` do PEŁNEJ karty `size×size`, a maskowanie
    /// następowało DOPIERO potem, więc "kadr" zdjęcia zakładał pełne koło,
    /// mimo że faktyczny otwór zajmuje tylko 37-63% karty — widoczny
    /// fragment wypadał dużo bardziej przybliżony/przesunięty niż
    /// widziany w wersji bez ramki). Teraz zdjęcie jest dopasowywane
    /// wprost do `frame.holeRect` (bounding box otworu, zmierzony z pliku
    /// maski) i pozycjonowane na jego środku, PRZED maskowaniem — ten sam
    /// kadr co w zwykłym kole, niezależnie od tego, jak mały jest otwór
    /// danej ramki. `self` musi być NIEOSTYLOWANYM `.resizable()
    /// .aspectRatio(contentMode: .fill)` obrazkiem (bez `.frame()`) — ten
    /// modyfikator sam dobiera rozmiar. Bez `holeRect` (stary zestaw
    /// `Seasonal*`, `.none`, programowe ramki) zwykłe `clipShape(Circle())`
    /// na pełnej karcie, jak dotąd.
    @ViewBuilder
    func avatarFramedPhoto(_ frame: AvatarFrame, size: CGFloat) -> some View {
        #if DEBUG
        if let hole = frame.holeRect, let maskName = frame.maskAssetName {
            let inner = size * frame.outerScale
            ZStack {
                self
                    .frame(width: inner * hole.width, height: inner * hole.height)
                    .position(x: inner * (hole.x + hole.width / 2), y: inner * (hole.y + hole.height / 2))
            }
            .frame(width: inner, height: inner)
            .mask(
                Image(maskName)
                    .resizable()
                    .frame(width: inner, height: inner)
            )
            .frame(width: size, height: size)
        } else {
            self.frame(width: size, height: size).clipShape(Circle())
        }
        #else
        self.frame(width: size, height: size).clipShape(Circle())
        #endif
    }
}
