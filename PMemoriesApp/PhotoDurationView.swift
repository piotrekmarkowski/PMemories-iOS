import SwiftUI

/// Ręczna obróbka zwykłego ZDJĘCIA (nie wideo/Live Photo) — user 30.07.2026:
/// "ktoś nie będzie chciał klipu, będzie chciał kilka fotek... będzie
/// potrzeba ustawianie długości wyświetlania każdego zdjęcia". `TrimView`
/// nie nadaje się dla zdjęć — cały jego UI (suwak zakresu) operuje na
/// `sourceDuration`, którego zwykłe zdjęcie po prostu nie ma (nie ma czego
/// "przycinać" w źródle). To osobny, prostszy arkusz: sam czas wyświetlania
/// + obrót/kadrowanie (te same dwa pola co reszta piątki Studio, `Trim
/// View.rotateAndCropControls` — świadomie zduplikowane, nie wydzielone do
/// wspólnej funkcji, ta sama zasada "konkretna duplikacja nad przedwczesną
/// abstrakcją" co `VideoComposer.resolveOverlaySourceURL`).
struct PhotoDurationView: View {
    @Binding var item: MediaItem
    /// Patrz `TrimView.isFirst` — pierwszy element sekwencji nie ma
    /// przejścia przed sobą.
    var isFirst: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let minDuration: Double = 0.5
    private let maxDuration: Double = 15

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Text("Photo")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { item.duration },
                        set: { item.duration = $0; item.isManuallyTrimmed = true }
                    ),
                    in: minDuration...maxDuration, step: 0.5
                )
                Text("\(L("Shown for")) \(format(item.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.isManuallyTrimmed {
                    Button("Restore automatic timing") {
                        item.isManuallyTrimmed = false
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 24)

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

            if !isFirst {
                VStack(spacing: 8) {
                    Divider()
                    Text("Transition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        transitionButton(label: L("Auto"), isSelected: item.transitionStyle == nil) {
                            item.transitionStyle = nil
                        }
                        // Premium style pominięte dla zwykłych userów, ale
                        // nie dla Foundera — patrz ten sam komentarz w
                        // `TrimView.transitionPicker`.
                        ForEach(TransitionStyle.allCases.filter { !$0.isPremium || TesterRegistry.hasPremiumUnlocked(AuthManager.shared.userIdentifier) }) { style in
                            transitionButton(label: style.label, isSelected: item.transitionStyle == style) {
                                item.transitionStyle = style
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(isFirst ? 420 : 510)])
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

    private func format(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}
