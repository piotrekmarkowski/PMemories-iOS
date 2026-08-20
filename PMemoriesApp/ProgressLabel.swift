import SwiftUI

/// Karta z paskiem postępu i procentem — zastępuje generyczny, nic-nie-
/// mówiący `ProgressView()` (bez wartości) przy dłuższych operacjach
/// (wczytywanie zdjęć, tworzenie klipu), gdzie user inaczej nie wie, czy
/// appka pracuje, czy się zawiesiła.
struct ProgressLabel: View {
    let title: String
    let progress: Double

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
            ProgressView(value: min(1, max(0, progress)))
                .frame(width: 160)
            Text("\(Int(min(1, max(0, progress)) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
