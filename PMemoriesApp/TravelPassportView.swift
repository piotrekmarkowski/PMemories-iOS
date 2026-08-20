import SwiftUI
import SwiftData
import UIKit

/// "Travel Passport" — kolekcja pieczątek, jedna per odwiedzony kraj (`Travel.
/// md`, pierwotny jednolinijkowy pomysł: "Travel Passport (kolekcja
/// pieczątek)"). Świadomie ODDZIELNY, ozdobny widok od listy "Kraje" w
/// Odznakach — te same dane (`PassportCountry`), inna prezentacja: stemple
/// zamiast zwykłej listy, żeby wyglądało jak prawdziwy paszport, nie kolejny
/// wpis w tabelce.
struct TravelPassportView: View {
    @Query(sort: \SavedTrip.createdAt) private var savedTrips: [SavedTrip]

    /// Link do publicznego profilu — LENIWY, generowany dopiero po
    /// tapnięciu (13.08.2026), ten sam wzorzec co link do udostępnienia
    /// podróży w `TripPlanningView.swift` (async wywołanie sieciowe nie
    /// może żyć wewnątrz `Transferable`, patrz komentarz tam).
    @State private var profileLinkURL: URL?
    @State private var isPreparingProfileLink = false
    @State private var profileLinkError: String?
    /// Okno udostępniania otwiera się SAMO gdy link jest gotowy (`onChange`
    /// niżej) — BUG znaleziony 13.08.2026 (user: "za drugim razem działa"):
    /// zamiana przycisku `Button` → `ShareLink` PO wygenerowaniu linku
    /// (wzorzec z `TripPlanningView`) tylko PRZYGOTOWUJE `ShareLink`, nie
    /// otwiera go automatycznie — pierwsze tapnięcie generuje link, dopiero
    /// DRUGIE faktycznie otwiera okno. Naprawa: JEDEN przycisk, ręczne
    /// prezentowanie `UIActivityViewController` przez `.onChange`, żeby
    /// okno pojawiło się samo zaraz po przygotowaniu linku.
    @State private var isShowingShareSheet = false

    private var countries: [PassportCountry] {
        TravelAchievementsCalculator.passportCountries(from: savedTrips)
    }

    var body: some View {
        Group {
            if countries.isEmpty {
                VStack(spacing: 12) {
                    Text("🛂")
                        .font(.system(size: 40))
                        .opacity(0.5)
                    Text("Your passport is empty")
                        .font(.title3.bold())
                    Text("Your first stamp will appear once you save a trip with a country")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text("\(countries.count) \(countries.count == 1 ? "stamp" : "stamps")")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(countries) { country in
                            PassportStampView(country: country)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Travel Passport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    prepareProfileLink()
                } label: {
                    if isPreparingProfileLink {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(countries.isEmpty || isPreparingProfileLink)
            }
        }
        // Link już GOTOWY (np. wygenerowany chwilę temu) → tapnięcie
        // otwiera okno OD RAZU, bez ponownego zapytania do serwera —
        // `prepareProfileLink()` woła się tylko gdy `profileLinkURL == nil`.
        .onChange(of: profileLinkURL) { _, newValue in
            if newValue != nil { isShowingShareSheet = true }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let profileLinkURL {
                ActivityShareSheet(items: [profileLinkURL])
            }
        }
        .alert(L("Couldn't create profile link"), isPresented: Binding(
            get: { profileLinkError != nil }, set: { if !$0 { profileLinkError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(profileLinkError ?? "")
        }
    }

    /// Wysyła aktualny snapshot statystyk na serwer i zamienia otrzymane ID
    /// w link — patrz komentarz przy `profileLinkURL`.
    private func prepareProfileLink() {
        // Link już gotowy z poprzedniego tapnięcia — otwórz OD RAZU, bez
        // nowego zapytania do serwera (`onChange` wyżej i tak by to
        // zrobiło samo, ale to unika zbędnego rok-trip sieciowego gdy user
        // tapnie drugi raz po zamknięciu arkusza).
        if profileLinkURL != nil {
            isShowingShareSheet = true
            return
        }
        isPreparingProfileLink = true
        Task {
            defer { isPreparingProfileLink = false }
            do {
                let achievements = TravelAchievementsCalculator.achievements(from: savedTrips)
                let score = TravelAchievementsCalculator.explorerScore(from: savedTrips)
                let dto = ExplorerProfileDTO(
                    displayName: AuthManager.shared.displayName ?? L("Explorer"),
                    explorerScoreTotal: score.total,
                    explorerScoreTier: score.tierName,
                    countries: countries.count,
                    cities: Int(achievements.first { $0.id == "cities" }?.currentValue ?? 0),
                    totalKm: score.totalKm,
                    tripsCount: savedTrips.count,
                    passport: countries.map {
                        ExplorerProfilePassportEntry(countryCode: $0.countryCode, countryName: $0.countryName, firstVisitDate: $0.firstVisitDate)
                    }
                )
                profileLinkURL = try await ExplorerProfileService.createProfileLink(for: dto)
            } catch {
                profileLinkError = error.localizedDescription
            }
        }
    }
}

/// Natywne okno udostępniania prezentowane RĘCZNIE (13.08.2026) — zamiast
/// `ShareLink` (który wymaga OSOBNEGO tapnięcia PO tym jak stanie się
/// dostępny, patrz komentarz przy `isShowingShareSheet`). Ten sam,
/// standardowy `UIActivityViewController` co pod spodem używa `ShareLink`,
/// tylko prezentowany od razu gdy link jest gotowy. Nie-`private`
/// (17.08.2026) — reużyty też w `TripPlanningView.swift`, TEN SAM bug
/// (Button→ShareLink wymaga drugiego tapnięcia) tam też wystąpił.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct PassportStampView: View {
    let country: PassportCountry

    /// Lekki, ale STAŁY (nie losowy przy każdym odświeżeniu) obrót per
    /// stempel — deterministyczny z kodu kraju, żeby wyglądało jak ręcznie
    /// odbite pieczątki, ale nie "migotało" przy przewijaniu listy.
    private var rotationDegrees: Double {
        let hash = country.countryCode.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(hash % 11) - 5
    }

    private var dateText: String {
        guard let date = country.firstVisitDate else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(CityGeocoder.flagEmoji(countryCode: country.countryCode))
                .font(.system(size: 34))
            Text(country.countryName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !dateText.isEmpty {
                Text(dateText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        )
        .foregroundStyle(Palette.blue)
        .rotationEffect(.degrees(rotationDegrees))
        .padding(6)
    }
}
