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
    /// Ramka awatara wybrana przez usera (28-30.08.2026, `AvatarFrame`) —
    /// WŁASNY WYBÓR MA PIERWSZEŃSTWO nad odznaką Foundera/Testera (30.08.2026,
    /// user: "moja funder jest tylko jedna ale jak bede mial ochote miec
    /// inna to chce tez to zrobic" — zmiana z poprzedniej zasady, gdzie
    /// Founder/Tester mieli sztywno narzucony wygląd bez możliwości
    /// wyboru). Korona/fiolka zostają tylko DOMYŚLNE — pokazują się
    /// dopiero gdy `selectedAvatarFrame == .none`, patrz przełącznik niżej.
    @AppStorage("selectedAvatarFrame") private var selectedAvatarFrameRawValue: String = AvatarFrame.none.rawValue
    /// "AI Director" (30.08.2026) — user: "w apce bedziemy miec mozliwosc z
    /// AI albo bez do wyboru przez uzytkownika". Domyślnie włączone; wyłączenie
    /// tu chowa pole tekstowe w `AIDirectorView` (zostają tylko presety) i
    /// wpływa na `AIDirectorEngine.availability` wszędzie w appce, nie tylko
    /// w edytorze.
    @AppStorage(AIDirectorEngine.aiEnabledKey) private var aiFeaturesEnabled: Bool = true

    private var selectedAvatarFrame: AvatarFrame {
        AvatarFrame(rawValue: selectedAvatarFrameRawValue) ?? .none
    }

    private static let founderIconName = "crown.fill"
    private static let testerIconName = "testtube.2"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Group {
                                if let avatarImage {
                                        Image(uiImage: avatarImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .avatarFramedPhoto(selectedAvatarFrame, size: 84)
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
                                // Odznaka wybranej ramki/testera/foundera
                                // (TODO.md 08.08.2026, priorytet odwrócony
                                // 30.08.2026 — patrz komentarz przy
                                // `selectedAvatarFrameRawValue`): WŁASNY
                                // wybór usera wygrywa zawsze gdy != .none;
                                // korona/fiolka Foundera/Testera to tylko
                                // domyślny wygląd, dopóki user niczego nie
                                // wybrał.
                                .overlay {
                                    if selectedAvatarFrame != .none {
                                        AvatarFrameBadge(frame: selectedAvatarFrame, avatarSize: 84)
                                    } else {
                                        switch TesterRegistry.badge(for: auth.userIdentifier) {
                                        case .founder:
                                            AvatarFrameOverlay(color: Palette.founderAccent, iconName: Self.founderIconName, avatarSize: 84)
                                        case .tester:
                                            AvatarFrameOverlay(color: Palette.testerAccent, iconName: Self.testerIconName, avatarSize: 84)
                                        case .none:
                                            EmptyView()
                                        }
                                    }
                                }
                            // Zmiana zdjęcia przeniesiona z pływającej
                            // ikonki aparatu w rogu awatara na zwykły
                            // przycisk tekstowy (29.08.2026, bug znaleziony
                            // na żywo: kamera i odznaka ramki lądowały w
                            // TYM SAMYM rogu, kamera (rysowana później)
                            // całkowicie zasłaniała koronę/fiolkę/ikonę
                            // ramki). Róg awatara należy teraz wyłącznie do
                            // odznaki.
                            PhotosPicker(selection: $avatarSelection, matching: .images) {
                                Text(avatarImage == nil ? L("Add Photo") : L("Change Photo"))
                                    .font(.caption)
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

                Section {
                    Toggle(L("AI Features"), isOn: $aiFeaturesEnabled)
                } footer: {
                    Text(L("Lets PMemories suggest an editing style (music mood, filter, transitions) from a short description you type. Runs entirely on your device — nothing is sent anywhere. Turn off to use manual presets only."))
                }

                // Avatar Frame NAD Templates (30.08.2026, user: "ramki
                // powinny byc nad tameplates") — teraz zwykły wiersz
                // `NavigationLink` zamiast modalnego `.sheet`, widoczny dla
                // WSZYSTKICH (w tym Foundera/Testera — patrz odwrócony
                // priorytet przy `selectedAvatarFrameRawValue` wyżej).
                Section {
                    NavigationLink {
                        AvatarFrameView(avatarImage: avatarImage)
                    } label: {
                        Label(L("Avatar Frame"), systemImage: "seal")
                    }
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
