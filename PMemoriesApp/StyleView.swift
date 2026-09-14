import SwiftUI

/// Zakładka "Style" w edytorze — 09.08.2026, user: "użytkownik sobie
/// wybiera jakie przejścia chce i ile, program automatycznie sam je
/// rozmieszcza, tak jak to robi teraz z tymi 3". Wcześniej placeholder
/// ("Style — coming soon"). Wybór wpływa TYLKO na klipy bez ręcznie
/// ustawionego stylu w Trim — `TransitionStyle.auto(forTransitionIndex:pool:)`
/// cykluje po zaznaczonych stylach zamiast po całej puli.
struct StyleView: View {
    @Binding var enabledTransitions: Set<TransitionStyle>
    /// Filtr kolorystyczny (09.08.2026, user: "coś w stylu retro") —
    /// pojedynczy wybór (nie multi-select jak przejścia), patrz `ColorStyle`/
    /// `ColorGrader`.
    @Binding var colorStyle: ColorStyle
    @Environment(\.dismiss) private var dismiss

    /// Premium przejścia odblokowane TYLKO dla Foundera już dziś (30.08.2026,
    /// user: "to bedzie zachowane dla premium i dla mnie") — patrz
    /// `TesterRegistry.hasPremiumUnlocked`.
    private var isPremiumUnlocked: Bool {
        TesterRegistry.hasPremiumUnlocked(AuthManager.shared.userIdentifier)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ColorStyle.allCases) { style in
                        Button {
                            colorStyle = style
                        } label: {
                            HStack {
                                Text(style.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if colorStyle == style {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L("Filter"))
                } footer: {
                    Text(L("Applies a color look to the whole movie. Adds a bit of extra export time."))
                }

                Section {
                    ForEach(TransitionStyle.allCases.filter { !$0.isPremium }) { style in
                        Button {
                            toggle(style)
                        } label: {
                            HStack {
                                Text(style.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if enabledTransitions.contains(style) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L("Transitions"))
                } footer: {
                    Text(L("Choose which transitions PMemories can use — it will spread the ones you pick automatically between your clips."))
                }

                // Premium przejścia (30.08.2026, user: "wprowadz jako
                // premium") — widoczne dla wszystkich, ale zablokowane
                // (kłódka) dopóki appka nie ma systemu płatności. WYJĄTEK:
                // Founder ma już dziś pełny dostęp na własnym telefonie
                // (user: "to bedzie zachowane dla premium i dla mnie") —
                // ten sam toggle/checkmark co zwykłe style, patrz
                // `isPremiumUnlocked`.
                Section {
                    ForEach(TransitionStyle.allCases.filter(\.isPremium)) { style in
                        if isPremiumUnlocked {
                            Button {
                                toggle(style)
                            } label: {
                                HStack {
                                    Text(style.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if enabledTransitions.contains(style) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.blue)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(style.label)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L("Premium Transitions"))
                } footer: {
                    Text(isPremiumUnlocked
                        ? L("Early access — unlocked just for the Founder for now.")
                        : L("Coming soon — unlock with a future PMemories subscription."))
                }
            }
            .navigationTitle(L("Style"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    /// Zawsze zostaje przynajmniej jeden zaznaczony — odznaczenie
    /// ostatniego byłoby ciche zablokowanie eksportu (pusta pula), więc
    /// zamiast alertu po prostu nie pozwalamy zejść do zera.
    private func toggle(_ style: TransitionStyle) {
        if enabledTransitions.contains(style) {
            guard enabledTransitions.count > 1 else { return }
            enabledTransitions.remove(style)
        } else {
            enabledTransitions.insert(style)
        }
    }
}
