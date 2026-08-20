import SwiftUI

/// Zakładka "Templates" — 02.08.2026, user: "urzytkownicy decyduja w co
/// ubieraja apke" — prosty picker skórki tła dla pozostałych zakładek
/// (Home/Studio/Travel/Library), zero automatycznego zgadywania na start
/// (patrz `AppSkin`/pamięć projektu — smart-detection wg lokalizacji
/// świadomie odłożone na później). Zastępuje wcześniejszy `PlaceholderTab`.
struct TemplatesView: View {
    @AppStorage("selectedAppSkin") private var selectedSkinRawValue: String = AppSkin.none.rawValue

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Templates")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Choose a subtle background skin for your tabs. \"Seasonal\" automatically changes with the time of year.")
                        .font(.subheadline)
                }
                .skinAwareHeading()

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppSkin.pickerCases) { skin in
                        SkinCard(skin: skin, isSelected: skin.rawValue == selectedSkinRawValue) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedSkinRawValue = skin.rawValue
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .tabSkinBackground()
    }
}

private struct SkinCard: View {
    let skin: AppSkin
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))

                if let thumbnailAssetName = skin.thumbnailAssetName {
                    Image(thumbnailAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // `.none` — kwadrat pokazujący dzisiejszy, zwykły ciemny
                    // wygląd bez żadnej skórki, żeby user widział że to
                    // realna, "pusta" opcja, nie brakujący obrazek.
                    Color.black.opacity(0.9)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

                Text(skin.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .multilineTextAlignment(.leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Palette.blue)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            // BUG znaleziony 02.08.2026 (user: karta zajmowała CAŁĄ
            // szerokość ekranu zamiast trzymać się kolumny siatki) —
            // `.aspectRatio(_, contentMode: .fit)` na zawartości bez
            // WŁASNEGO intrinsic rozmiaru (Image z `.fill`, gradient) dawał
            // nieprzewidywalny, zbyt duży wynik w `LazyVGrid`. Zwykła STAŁA
            // wysokość + `maxWidth: .infinity` jest jednoznaczna — karta
            // zawsze dokładnie wypełnia przydzieloną kolumnę.
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Palette.blue : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
