import SwiftUI

/// Picker ramki awatara (29.08.2026) — ten sam duch co `TemplatesView`
/// (grid, user sam wybiera, zero automatycznego zgadywania), tylko dla
/// `AvatarFrame` zamiast `AppSkin`. Świadomie dostępny dla WSZYSTKICH
/// userów już teraz, bez blokady Premium — appka jeszcze nie ma systemu
/// płatności, user: "narazie na testach full dostęp, później będziemy to
/// rozdzielać" (stopniowe odblokowywanie przez osiągnięcia/Premium to
/// osobny, świadomie odłożony temat, patrz `Docs/TODO.md`).
struct AvatarFrameView: View {
    @AppStorage("selectedAvatarFrame") private var selectedFrameRawValue: String = AvatarFrame.none.rawValue
    let avatarImage: UIImage?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    // Bez własnego `NavigationStack`/`.toolbar` Done (30.08.2026) — teraz
    // wpięty jako `NavigationLink` w liście Profilu (ten sam wzorzec co
    // `TemplatesView`), nie modalny `.sheet`. Wraca się zwykłym przyciskiem
    // "Wstecz" z rodzicielskiego `NavigationStack`, nie potrzeba osobnego
    // Done/`dismiss()`.
    /// Darmowe: 10 prostych, programowo rysowanych ramek + "Brak ramki".
    /// Stary zestaw `seasonal*` (Beach Lover, Island Hopper…) też WYKLUCZONY
    /// stąd — user (05.09.2026): "te ramki maja byc w premium nie wyciete
    /// kompletnie" — NIE chowamy ich, tylko przenosimy do "Seasonal &
    /// Limited" niżej razem z nowym zestawem (`isLegacySeasonalPreview` w
    /// `seasonalPremiumFrames`), zamiast zostawiać w Free obok prawdziwych
    /// darmowych ramek gdzie mylą się z nowszym, ładniejszym zestawem.
    private var gridFrames: [AvatarFrame] {
        #if DEBUG
        return AvatarFrame.allCases.filter { !$0.isPremiumBadge && !$0.isLegacySeasonalPreview }
        #else
        return AvatarFrame.allCases
        #endif
    }

    #if DEBUG
    /// Cały zestaw `PremiumBadge*` (28 ramek — 13 postaciowych + 15
    /// okazjonalnych) WYCOFANY z pickera (06.09.2026, user: "koniec z nowymi
    /// ramkami wyrzucamy nowe ramki... nie potrafisz ich ogarnac i nie
    /// spelniaja wymogu i standardu wiec nie mozemy ich miec" — po
    /// wielogodzinnej serii poprawek maski/skalowania/otworu ostateczna
    /// decyzja usera to całkowita rezygnacja z tego zestawu, nie kolejna
    /// łatka). Assety zostają na dysku (nieusunięte, na wypadek powrotu do
    /// tematu), ale żaden `PremiumBadge*` case nie pojawia się już w UI.
    ///
    /// Zostaje WYŁĄCZNIE stary zestaw `seasonal*` (Beach Lover, Island
    /// Hopper… stworzony 30.08.2026, kilka dni przed `PremiumBadge*") —
    /// widoczny nadal TYLKO dla Foundera, jak ustalono wcześniej.
    private var seasonalPremiumFrames: [AvatarFrame] {
        guard TesterRegistry.badge(for: AuthManager.shared.userIdentifier) == .founder else { return [] }
        return AvatarFrame.allCases.filter { $0.isLegacySeasonalPreview }
    }
    #endif

    private func gridSection(title: String, frames: [AvatarFrame]) -> some View {
        Group {
            if !frames.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.headline)
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(frames) { frame in
                            AvatarFrameCard(
                                frame: frame,
                                avatarImage: avatarImage,
                                isSelected: frame.rawValue == selectedFrameRawValue
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFrameRawValue = frame.rawValue
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
    }

    var body: some View {
        ScrollView {
            gridSection(title: L("Free"), frames: gridFrames)

            #if DEBUG
            gridSection(title: "✨ Seasonal & Limited", frames: seasonalPremiumFrames)
            #endif
        }
        .navigationTitle(L("Avatar Frame"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AvatarFrameCard: View {
    let frame: AvatarFrame
    let avatarImage: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    /// Wspólny rozmiar KAŻDEJ karty w pickerze (05.09.2026, user: "dlaczego
    /// ramki nie sa jednej wielkosci... te co sa za free maja dobry
    /// rozmiar, trzeba ogarnac tez reszte zeby byly takie same") — pierścień
    /// zawsze renderuje się na dokładnie `avatarSize`, identycznie jak
    /// proste, darmowe ramki.
    private let avatarSize: CGFloat = 68

    private var isThickLegacyRing: Bool {
        #if DEBUG
        return frame.isLegacySeasonalPreview
        #else
        return false
        #endif
    }

    // 06.09.2026, user: "to co robilismy do ramek premium nic nie
    // dzialalo, uzyj kodu ktorego mamy w ramkach ktore sa za free" —
    // stary zestaw `seasonal*` (i, po fixie 11.09.2026, KAŻDA ramka w
    // Release) renderuje się DOKŁADNIE tą samą ścieżką co darmowe,
    // programowe ramki: zdjęcie wypełnia całą kartę, `AvatarFrameBadge`
    // (poniżej) sam dobiera rozmiar PNG przez `overlayScaleFactor`.
    private var freeStyleAvatar: some View {
        avatarPreview
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay {
                if frame != .none {
                    AvatarFrameBadge(frame: frame, avatarSize: avatarSize)
                } else {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // 11.09.2026: `frame.maskAssetName` istnieje TYLKO w
                // `#if DEBUG` (`AvatarFrame.swift`) — ta gałąź musi być tak
                // samo ograniczona, inaczej Release (`xcodebuild archive`,
                // dopiero przy wrzucaniu builda 26 na TestFlight, pierwszy
                // raz od 30.08) w ogóle się nie kompiluje ("value of type
                // 'AvatarFrame' has no member 'maskAssetName'") — nikt tego
                // nie złapał wcześniej, bo między buildami 25 i 26 cała ta
                // ścieżka testowana była tylko w Debug.
                #if DEBUG
                if frame.maskAssetName != nil {
                    // Druga generacja `PremiumBadge*` (05.09.2026, user:
                    // screenshot Globetrottera z globusem zalanym zdjęciem;
                    // 06.09.2026, user: prawdziwe zdjęcie pokazało uciętą
                    // głowę na WSZYSTKICH ramkach Premium) — zdjęcie jest
                    // teraz dopasowywane wprost do `holeRect` (bounding box
                    // faktycznego otworu, nie całej karty) i pozycjonowane
                    // na jego środku, PRZED przycięciem prawdziwym
                    // kształtem dziury (`avatarFramedPhoto`). Pierścień na
                    // wierzchu w tym samym układzie współrzędnych.
                    avatarPreview
                        .avatarFramedPhoto(frame, size: avatarSize)
                        .overlay {
                            AvatarFrameBadge(frame: frame, avatarSize: avatarSize)
                        }
                } else {
                    freeStyleAvatar
                }
                #else
                freeStyleAvatar
                #endif
                Text(frame.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // 06.09.2026, user: "podpisy pod ramkami... przy
                    // specjalnych niektore nachodza bo sa grubsze ramki" —
                    // pierścień starego zestawu `seasonal*` renderuje się na
                    // avatarSize*overlayScaleFactor (68×1.7≈116pt), więc
                    // wystaje ~24pt poza 68pt kartę i zachodzi na podpis
                    // zaraz pod spodem. Dodatkowy odstęp TYLKO dla tego
                    // zestawu, żeby nie zmieniać wyglądu darmowych ramek.
                    .padding(.top, isThickLegacyRing ? 18 : 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Palette.blue : Color.secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let avatarImage {
            Image(uiImage: avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Palette.heroGradient)
        }
    }
}
