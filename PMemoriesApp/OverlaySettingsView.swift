import SwiftUI

/// Ustawienia jednej nakładki "picture-in-picture" — Faza 1 "prawdziwego
/// multi-tracku" (patrz `Docs/Studio.md`). Wzorowane bezpośrednio na
/// `TrimView.swift` (arkusz, dyskretne przyciski presetów zamiast
/// swobodnego przeciągania na płótnie — ta sama zasada "ręczna kontrola
/// zawsze dostępna, przez prosty arkusz" co reszta Studio).
struct OverlaySettingsView: View {
    @Binding var overlay: OverlayItem
    /// Całkowity czas finalnego filmiku (sekundy) — do ograniczenia suwaków
    /// czasu startu/długości.
    let totalDuration: Double
    /// Zakresy CZASOWE pozostałych nakładek (bez tej edytowanej) — Faza 1
    /// zakazuje nachodzenia nakładek na siebie nawzajem, suwak startu jest
    /// względem nich przycinany.
    let otherOverlayRanges: [(start: Double, end: Double)]
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Text("PiP Overlay")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            timingSection
            cornerPicker
            sizePicker

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete overlay", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(420)])
    }

    /// Górna granica startu — nakładka musi się zmieścić w pozostałym
    /// czasie filmiku, dodatkowo przycięta żeby nie wjechać w sąsiednią
    /// nakładkę (Faza 1: bez nachodzenia w czasie).
    private var maxStart: Double {
        let roomLimit = max(0, totalDuration - overlay.duration)
        let nextOtherStart = otherOverlayRanges
            .map(\.start)
            .filter { $0 >= overlay.globalStartTime }
            .min()
        guard let nextOtherStart else { return roomLimit }
        return min(roomLimit, max(0, nextOtherStart - overlay.duration))
    }

    private var timingSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                HStack {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(format(overlay.globalStartTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $overlay.globalStartTime,
                    in: 0...max(0.01, maxStart)
                )
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Length")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(format(overlay.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $overlay.duration,
                    in: 0.5...max(0.5, min(15, totalDuration - overlay.globalStartTime))
                )
            }
        }
        .padding(.horizontal, 24)
    }

    /// 4 stałe rogi zamiast swobodnego przeciągania — Faza 1 (patrz plan).
    private var cornerPicker: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Position")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(OverlayCorner.allCases) { corner in
                    Button {
                        overlay.corner = corner
                    } label: {
                        Image(systemName: cornerIcon(corner))
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                overlay.corner == corner ? Palette.blue.opacity(0.2) : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func cornerIcon(_ corner: OverlayCorner) -> String {
        switch corner {
        case .topLeading: return "arrow.up.left.square"
        case .topTrailing: return "arrow.up.right.square"
        case .bottomLeading: return "arrow.down.left.square"
        case .bottomTrailing: return "arrow.down.right.square"
        }
    }

    /// Presety zamiast dowolnego suwaka — user zwykle chce jednego z kilku
    /// znanych rozmiarów, ten sam wzorzec co `TrimView.speedPicker`.
    private var sizePicker: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(sizePresets, id: \.label) { preset in
                    Button {
                        overlay.sizeScale = preset.value
                    } label: {
                        Text(preset.label)
                            .font(.caption.weight(overlay.sizeScale == preset.value ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                overlay.sizeScale == preset.value ? Palette.blue.opacity(0.2) : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var sizePresets: [(label: String, value: Double)] {
        [(L("Small"), 0.28), (L("Medium"), 0.38), (L("Large"), 0.50)]
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}
