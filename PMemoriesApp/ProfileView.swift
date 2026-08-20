import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Profil — wybór języka appki (`AppLanguage`). User 31.07.2026: usunięta
/// wcześniejsza sekcja "Home Countries" (kraje domowe wykluczane z Explorer
/// Score/odznak/paszportu) — user uznał ją za niepotrzebną, kraj zamieszkania
/// liczy się teraz tak samo jak każdy inny odwiedzony kraj.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: AppLanguage = AppLanguage.current
    /// Wybór w Pickerze NIE stosuje się od razu — user 31.07.2026 chce
    /// potwierdzenia, bo appka i tak musi się zamknąć żeby zmiana zadziałała
    /// (String Catalog resolwuje język raz, przy starcie procesu — patrz
    /// `AppLanguage.swift`). Trzymane osobno od `selectedLanguage`, żeby
    /// Anuluj mogło cofnąć Picker do faktycznie aktywnego języka.
    @State private var pendingLanguage: AppLanguage?
    @State private var avatarImage: UIImage? = AvatarStorage.load()
    @State private var avatarSelection: PhotosPickerItem?
    /// Zdjęcie świeżo wybrane z pickera, jeszcze niekadrowane (10.08.2026,
    /// TODO.md 08.08 — "brak jakiegokolwiek kadrowania/dopasowania").
    /// Osobne od `avatarImage` (już zapisany, skadrowany wynik) — dopóki
    /// user nie zatwierdzi crop w `AvatarCropView`, `AvatarStorage` się nie
    /// zmienia.
    @State private var croppingImage: UIImage?
    // BUG znaleziony 09.08.2026 (fallback bez zdjęcia pokazywał
    // zahardcodowane "P" — ta sama klasa błędu co powitanie "Good
    // afternoon, Piotr") — inicjał musi pochodzić z faktycznie
    // zalogowanego usera, nie z developera appki.
    @StateObject private var auth = AuthManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let avatarImage {
                                        Image(uiImage: avatarImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 84, height: 84)
                                            .clipShape(Circle())
                                    } else if let initial = auth.displayName?.first {
                                        Text(String(initial))
                                            .font(.system(size: 32, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(width: 84, height: 84)
                                            .background(Palette.heroGradient, in: Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(.white)
                                            .frame(width: 84, height: 84)
                                            .background(Palette.heroGradient, in: Circle())
                                    }
                                }
                                // Odznaka testera (TODO.md 08.08.2026) —
                                // `TesterRegistry`, ręcznie utrzymywana
                                // lista Sign in with Apple identyfikatorów,
                                // appka nie ma innego źródła "kto testuje".
                                .overlay {
                                    if TesterRegistry.isTester(auth.userIdentifier) {
                                        Circle().stroke(Palette.heroGradient, lineWidth: 3)
                                    }
                                }
                                if TesterRegistry.isTester(auth.userIdentifier) {
                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white, Palette.purple)
                                        .background(Circle().fill(.white))
                                        .offset(x: -26, y: 4)
                                }
                                PhotosPicker(selection: $avatarSelection, matching: .images) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(.white, Palette.blue)
                                        .background(Circle().fill(.white))
                                }
                            }
                            if avatarImage != nil {
                                Button(role: .destructive) {
                                    AvatarStorage.remove()
                                    avatarImage = nil
                                } label: {
                                    Text("Remove photo")
                                        .font(.caption)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                .onChange(of: avatarSelection) { _, newValue in
                    guard let newValue else { return }
                    Task {
                        guard let data = try? await newValue.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else { return }
                        croppingImage = image
                        avatarSelection = nil
                    }
                }
                .fullScreenCover(isPresented: .init(
                    get: { croppingImage != nil },
                    set: { if !$0 { croppingImage = nil } }
                )) {
                    if let croppingImage {
                        AvatarCropView(image: croppingImage) { cropped in
                            AvatarStorage.save(cropped)
                            avatarImage = cropped
                            self.croppingImage = nil
                        } onCancel: {
                            self.croppingImage = nil
                        }
                    }
                }

                Section {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .onChange(of: selectedLanguage) { oldValue, newValue in
                        guard newValue != oldValue else { return }
                        pendingLanguage = newValue
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Defaults to your phone's language. Changing this closes the app — reopen it to see the new language.")
                }

                // Templates przeniesione tu z dolnego paska (11.08.2026) —
                // jego miejsce zajęło Trip Planning. `TemplatesView` nie ma
                // własnego `NavigationStack`/`.navigationTitle`, więc wpina
                // się w istniejący `NavigationStack` Profilu bez adaptacji.
                Section {
                    NavigationLink {
                        TemplatesView()
                    } label: {
                        Label("Templates", systemImage: "square.grid.2x2")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Change language and close the app?",
                isPresented: Binding(
                    get: { pendingLanguage != nil },
                    set: { if !$0 { pendingLanguage = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    selectedLanguage = AppLanguage.current
                    pendingLanguage = nil
                }
                // iOS nie pozwala appce samej się ponownie uruchomić (żaden
                // publiczny API do tego) — najbliższe możliwe: zastosować
                // język i zamknąć proces, user musi jeszcze raz stuknąć
                // ikonkę. Krótkie opóźnienie, żeby alert zdążył się zamknąć
                // przed twardym `exit`.
                Button("Change & Close", role: .destructive) {
                    if let pendingLanguage {
                        AppLanguage.apply(pendingLanguage)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        exit(0)
                    }
                }
            } message: {
                Text("Reopen PMemories afterwards to see it in the new language.")
            }
        }
    }
}
