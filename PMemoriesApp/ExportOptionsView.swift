import SwiftUI

/// Wybór jakości/rozdzielczości przed eksportem — ostatnia z pięciu
/// pierwotnych funkcji Studio (`Docs/Studio.md`).
struct ExportOptionsView: View {
    @Binding var quality: ExportQuality
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Text("Export Quality")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Picker("Quality", selection: $quality) {
                ForEach(ExportQuality.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            // 15.09.2026 — patrz `AnalyticsLogger`. 4K to funkcja idąca do
            // Premium (`Pricing.md`) — appka dziś nie blokuje jej wyboru,
            // loguje ZAMIAR (kto w ogóle sięga po najwyższą jakość).
            .onChange(of: quality) { _, newValue in
                if newValue == .uhd4k {
                    AnalyticsLogger.log(.premiumFeatureTapped(feature: "export_4k", source: "studio"))
                }
            }

            Text("Higher quality means a larger file and a longer export time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Export", action: onExport)
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)

            Spacer(minLength: 0)
        }
        .padding()
        // 15.09.2026 — patrz `AnalyticsLogger`.
        .onAppear {
            AnalyticsLogger.log(.premiumFeatureViewed(feature: "export_quality", source: "studio"))
        }
    }
}
