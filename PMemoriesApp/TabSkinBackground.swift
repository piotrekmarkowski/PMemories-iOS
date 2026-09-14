import SwiftUI

/// Subtelne tło zakładki wg wybranej `AppSkin` — 02.08.2026, user: "kazda
/// zakladka jest teraz ciemna dobrze by bylo zeby miala skorke ale nie taka
/// co bedzie bardzo mieszac musi byc delikatna". Rozmycie + ciemna nakładka
/// (nie surowe zdjęcie) — zawartość zakładki (karty/tekst) zostaje w pełni
/// czytelna, obrazek jest ledwo zauważalnym klimatem w tle, nie tapetą na
/// pierwszym planie.
///
/// Klucz `UserDefaults`/`@AppStorage` wspólny dla WSZYSTKICH zakładek —
/// jedna zmiana w Templates natychmiast odświeża tło wszędzie (SwiftUI
/// obserwuje ten sam klucz w każdym miejscu użycia), bez osobnego
/// mechanizmu powiadomień.
private struct TabSkinBackground: ViewModifier {
    @AppStorage("selectedAppSkin") private var selectedSkinRawValue: String = AppSkin.none.rawValue

    func body(content: Content) -> some View {
        content.background(alignment: .center) {
            if let skin = AppSkin(rawValue: selectedSkinRawValue), let assetName = skin.currentAssetName {
                GeometryReader { proxy in
                    // Ramka WIĘKSZA niż faktyczny rozmiar + rozmycie PRZED
                    // przycięciem do docelowego rozmiaru — standardowy trik
                    // przeciw widocznej, jaśniejszej krawędzi rozmycia na
                    // brzegu ekranu (rozmycie po przycięciu rozmywałoby sam
                    // twardy brzeg, nie tylko treść obrazka).
                    // 22px/55% → 8px/30% → 5px/18% (02.08.2026) — próba z
                    // 9px/24% + jasność/nasycenie -10% na zewnętrzną
                    // sugestię WYCOFANA w tej samej sesji (user, po
                    // przetestowaniu na żywo: "to co napisalem nie podoba
                    // mi sie, wczesniej bylo lepsze") — mimo że sam to
                    // zaproponował, rezultat na żywym urządzeniu wypadł
                    // gorzej niż poprzedni stan. Zostaje 5px/18%, bez
                    // jasności/nasycenia — NIE próbować tej samej zmiany
                    // ponownie bez wyraźnej nowej prośby.
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width + 20, height: proxy.size.height + 20)
                        .blur(radius: 5)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(Color.black.opacity(0.18))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: selectedSkinRawValue)
                }
                .ignoresSafeArea()
            } else {
                // Stan domyślny/brak skórki (22.08.2026, user: "bez skorki
                // jest strasznie jednolite [tło], nie widac chmurek") — był
                // kompletnie pusty `if let` bez gałęzi `else`, więc ekran
                // spadał na czysto biały systemowy background. Świadomie
                // BEZ ciemnej nakładki 0.18 jak realne skórki wyżej — ten
                // obrazek jest już z założenia jasny/pastelowy (żeby nie
                // konkurować z prawdziwymi zdjęciowymi skórkami), dociemnienie
                // zrobiłoby z niego szarą mgłę zamiast czystego nieba.
                GeometryReader { proxy in
                    Image("DefaultClouds")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension View {
    /// Dokleja subtelne tło aktualnie wybranej skórki — użyte na root każdej
    /// z głównych zakładek (Home/Studio/Travel/Library/Templates), NIE
    /// centralnie na jednym wspólnym kontenerze: `List` (Travel Map,
    /// Library) ma własne, nieprzezroczyste tło systemowe które inaczej
    /// zasłoniłoby skórkę — stąd `.scrollContentBackground(.hidden)` musi
    /// iść w parze z tym modyfikatorem tam, gdzie jest `List`.
    func tabSkinBackground() -> some View {
        modifier(TabSkinBackground())
    }

    /// Nagłówki sekcji siedzące BEZPOŚREDNIO na tle zakładki (nie na
    /// karcie) — 02.08.2026, user: "w zależności od tego jakie jest tło
    /// napisy musimy dać bardziej widoczne... białe jeśli się wybierze
    /// jakieś tło będą idealne". `.primary` (czarny w jasnym trybie
    /// systemowym) nie ma nic wspólnego z jasnością ZDJĘCIA w tle — biały +
    /// delikatny cień jest niezawodny niezależnie od tego JAKA skórka jest
    /// wybrana. Bez aktywnej skórki zostaje zwykłe `.primary`.
    func skinAwareHeading() -> some View {
        modifier(SkinAwareHeading())
    }
}

private struct SkinAwareHeading: ViewModifier {
    @AppStorage("selectedAppSkin") private var selectedSkinRawValue: String = AppSkin.none.rawValue

    private var hasActiveSkin: Bool {
        AppSkin(rawValue: selectedSkinRawValue)?.currentAssetName != nil
    }

    func body(content: Content) -> some View {
        content
            // 23.08.2026 — realny bug report (zrzut z telefonu w trybie
            // ciemnym): `.primary` w Dark Mode robi się biały, ale
            // "DefaultClouds" (brak aktywnej skórki) jest ZAWSZE jasne/
            // pastelowe, niezależnie od trybu systemowego — biały tekst na
            // jasnym niebie był nieczytelny. To tło nigdy nie ciemnieje, więc
            // tekst nad nim też nie powinien podążać za systemowym trybem —
            // stały ciemny kolor zamiast `.primary` W TYM jednym przypadku
            // (aktywne skórki zdjęciowe dalej używają `.white`, bez zmian).
            .foregroundStyle(AppSkin.skinAwareTextColor())
            .shadow(color: .black.opacity(hasActiveSkin ? 0.35 : 0), radius: 4, y: 1)
    }
}
