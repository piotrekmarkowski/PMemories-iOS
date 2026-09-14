import SwiftUI
import PhotosUI
import UIKit

/// Lista slotów zdjęć plakatu "My Travel Journey" z opcją ręcznej podmiany
/// (09.09.2026, user: "musi byc opcja wybierania zdjec... powinnismy miec
/// opcje zmiany jesli nam sie ono nie podoba" — konkretny przypadek:
/// Gatwick jako JEDYNE zdjęcie całej podróży, automatyczny dobór nie ma z
/// czego wybrać lepszego). Zmienia TYLKO które zdjęcie reprezentuje dany
/// kraj na plakacie — miejsce/kraj/podpis zostają prawdziwe, pochodzące z
/// danych podróży (patrz komentarz przy `TravelJourneyPosterView.
/// photoOverrides`).
struct PosterPhotoCustomizationView: View {
    fileprivate struct Slot: Identifiable {
        let id: String
        let code: String
        let image: UIImage
        let caption: String
    }

    let polaroids: [PosterPolaroidDescribable]
    let onChange: (_ code: String, _ newIdentifier: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickerTargetCode: String?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var isResolvingSelection = false

    private var slots: [Slot] {
        polaroids.map { Slot(id: $0.id, code: $0.code, image: $0.image, caption: $0.caption) }
    }

    var body: some View {
        NavigationStack {
            List(slots) { slot in
                HStack(spacing: 14) {
                    Image(uiImage: slot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(slot.caption)
                        .font(.subheadline)
                    Spacer()
                    PhotosPicker(
                        selection: Binding(
                            get: { pickerTargetCode == slot.code ? pickerSelection : nil },
                            set: { newValue in
                                pickerTargetCode = slot.code
                                pickerSelection = newValue
                            }
                        ),
                        matching: .images, photoLibrary: .shared()
                    ) {
                        if isResolvingSelection && pickerTargetCode == slot.code {
                            ProgressView()
                        } else {
                            Text(L("Change"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(isResolvingSelection)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(L("Customize Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .onChange(of: pickerSelection) { _, newValue in
                guard let newValue, let code = pickerTargetCode else { return }
                Task { await applySelection(newValue, forCode: code) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func applySelection(_ item: PhotosPickerItem, forCode code: String) async {
        guard let identifier = item.itemIdentifier else {
            pickerSelection = nil
            return
        }
        isResolvingSelection = true
        onChange(code, identifier)
        pickerSelection = nil
        pickerTargetCode = nil
        isResolvingSelection = false
    }
}

/// Minimalny widok `PolaroidPhoto` (prywatny w `TravelJourneyPosterView`)
/// potrzebny tu — osobny protokół zamiast eksportowania samego typu, żeby
/// nie zmieniać jego dostępności gdzie indziej.
protocol PosterPolaroidDescribable {
    var id: String { get }
    var code: String { get }
    var image: UIImage { get }
    var caption: String { get }
}
