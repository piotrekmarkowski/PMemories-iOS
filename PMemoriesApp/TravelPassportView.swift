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
    @Query private var savedProjects: [SavedProject]

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
                let score = TravelAchievementsCalculator.explorerScore(from: savedTrips, projects: savedProjects)
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

/// Nazwy assetów World Travel Stickers (03.09.2026, rozszerzone o Azję
/// tego samego dnia) — TYMCZASOWY podgląd na żywo na urządzeniu. Docelowo
/// osobna, premium sekcja (istniejące pieczątki niżej zostają darmowe) — to
/// mapowanie jest tu tylko po to, żeby user mógł zobaczyć jakość grafik na
/// prawdziwym ekranie zamiast w plikach PNG.
let worldStickerAssetByCountryCode: [String: String] = [
    "DE": "sticker_germany", "GR": "sticker_greece", "HU": "sticker_hungary",
    "IS": "sticker_iceland", "IE": "sticker_ireland", "IT": "sticker_italy",
    "XK": "sticker_kosovo", "LV": "sticker_latvia", "LI": "sticker_liechtenstein",
    "LT": "sticker_lithuania", "LU": "sticker_luxembourg", "MT": "sticker_malta",
    "MD": "sticker_moldova", "MC": "sticker_monaco", "ME": "sticker_montenegro",
    "AL": "sticker_albania", "AD": "sticker_andorra", "AT": "sticker_austria",
    "BY": "sticker_belarus", "BE": "sticker_belgium", "BA": "sticker_bosnia_and_herzegovina",
    "BG": "sticker_bulgaria", "HR": "sticker_croatia", "CY": "sticker_cyprus",
    "CZ": "sticker_czechia", "DK": "sticker_denmark", "EE": "sticker_estonia",
    "FI": "sticker_finland", "FR": "sticker_france", "GE": "sticker_georgia",
    "NL": "sticker_netherlands", "MK": "sticker_north_macedonia", "NO": "sticker_norway",
    "PL": "sticker_poland", "PT": "sticker_portugal", "RO": "sticker_romania",
    "RU": "sticker_russia", "SM": "sticker_san_marino", "RS": "sticker_serbia",
    "SK": "sticker_slovakia", "SI": "sticker_slovenia", "ES": "sticker_spain",
    "SE": "sticker_sweden", "CH": "sticker_switzerland", "TR": "sticker_turkiye",
    "AZ": "sticker_azerbaijan", "VA": "sticker_vatican_city", "UA": "sticker_ukraine",
    // Anglia/Szkocja/Walia/Irlandia Płn. (04.09.2026) — podłączone przez
    // syntetyczne klucze "GB-ENG" itd. z `TravelAchievementsCalculator.
    // passportCountries`, NIE przez prawdziwy kod ISO (którego dla nich nie
    // ma, wszystko to "GB"). Te klucze nigdy nie trafiają do `flagEmoji`
    // (ma już bezpieczne domyślne 🌍 dla kodów innych niż 2 znaki).
    "GB-ENG": "sticker_england", "GB-SCT": "sticker_scotland",
    "GB-WLS": "sticker_wales", "GB-NIR": "sticker_northern_ireland",

    // Azja (43 nowych, 03.09.2026) — Türkiye/Azerbaijan/Cyprus/Georgia z tej
    // planszy pominięte, bo już były w zestawie Europy.
    "QA": "sticker_qatar", "SA": "sticker_saudi_arabia", "SG": "sticker_singapore",
    "KR": "sticker_south_korea", "LK": "sticker_sri_lanka", "SY": "sticker_syria",
    "TJ": "sticker_tajikistan", "TH": "sticker_thailand", "TL": "sticker_timor-leste",
    "TM": "sticker_turkmenistan", "AE": "sticker_united_arab_emirates", "UZ": "sticker_uzbekistan",
    "VN": "sticker_vietnam", "YE": "sticker_yemen",
    "AF": "sticker_afghanistan", "AM": "sticker_armenia", "BH": "sticker_bahrain",
    "BT": "sticker_bhutan", "BN": "sticker_brunei", "KH": "sticker_cambodia",
    "CN": "sticker_china", "IN": "sticker_india", "ID": "sticker_indonesia",
    "IR": "sticker_iran", "IQ": "sticker_iraq", "IL": "sticker_israel", "JP": "sticker_japan",
    "JO": "sticker_jordan", "KZ": "sticker_kazakhstan", "KW": "sticker_kuwait",
    "KG": "sticker_kyrgyzstan", "LA": "sticker_laos", "LB": "sticker_lebanon",
    "MY": "sticker_malaysia", "MV": "sticker_maldives", "MN": "sticker_mongolia",
    "MM": "sticker_myanmar", "NP": "sticker_nepal", "KP": "sticker_north_korea",
    "OM": "sticker_oman", "PK": "sticker_pakistan", "PS": "sticker_palestine",
    "PH": "sticker_philippines",
    // Dwa brakujące do kompletu Azji (03.09.2026, user zauważył że plansze
    // się nie zgadzały z pełną listą 48 państw): Bangladesz i Tajwan.
    "BD": "sticker_bangladesh", "TW": "sticker_taiwan",

    // Afryka (54, 03.09.2026) — zweryfikowane jako komplet względem pełnej
    // listy 54 uznanych państw.
    "DZ": "sticker_algeria", "AO": "sticker_angola", "BJ": "sticker_benin",
    "BW": "sticker_botswana", "BF": "sticker_burkina_faso", "BI": "sticker_burundi",
    "CV": "sticker_cabo_verde", "CM": "sticker_cameroon", "CF": "sticker_central_african_republic",
    "TD": "sticker_chad", "KM": "sticker_comoros", "CG": "sticker_congo",
    "CD": "sticker_democratic_republic_of_the_congo", "DJ": "sticker_djibouti", "EG": "sticker_egypt",
    "GQ": "sticker_equatorial_guinea", "ER": "sticker_eritrea", "SZ": "sticker_eswatini",
    "ET": "sticker_ethiopia", "GA": "sticker_gabon", "GM": "sticker_gambia",
    "GH": "sticker_ghana", "GN": "sticker_guinea", "GW": "sticker_guinea-bissau",
    "CI": "sticker_côte_d'ivoire", "KE": "sticker_kenya", "LS": "sticker_lesotho",
    "LR": "sticker_liberia", "LY": "sticker_libya", "MG": "sticker_madagascar",
    "MW": "sticker_malawi", "ML": "sticker_mali", "MR": "sticker_mauritania",
    "MU": "sticker_mauritius", "MA": "sticker_morocco", "MZ": "sticker_mozambique",
    "NA": "sticker_namibia", "NE": "sticker_niger", "NG": "sticker_nigeria",
    "RW": "sticker_rwanda", "ST": "sticker_são_tomé_and_príncipe", "SN": "sticker_senegal",
    "SC": "sticker_seychelles", "SL": "sticker_sierra_leone", "SO": "sticker_somalia",
    "ZA": "sticker_south_africa", "SS": "sticker_south_sudan", "SD": "sticker_sudan",
    "TZ": "sticker_tanzania", "TG": "sticker_togo", "TN": "sticker_tunisia",
    "UG": "sticker_uganda", "ZM": "sticker_zambia", "ZW": "sticker_zimbabwe",

    // Specjalne (04.09.2026) — nie standardowe kraje ISO, ale user chciał je mieć.
    "AQ": "sticker_antarctica", "GL": "sticker_greenland",

    // Ameryki i Oceania (66, 04.09.2026).
    "AG": "sticker_antigua_and_barbuda", "AR": "sticker_argentina", "BS": "sticker_bahamas",
    "BB": "sticker_barbados", "BZ": "sticker_belize", "BO": "sticker_bolivia",
    "BR": "sticker_brazil", "CA": "sticker_canada", "CL": "sticker_chile",
    "CO": "sticker_colombia", "CR": "sticker_costa_rica", "CU": "sticker_cuba",
    "DM": "sticker_dominica", "DO": "sticker_dominican_republic", "EC": "sticker_ecuador",
    "SV": "sticker_el_salvador", "GD": "sticker_grenada", "GT": "sticker_guatemala",
    "GY": "sticker_guyana", "HT": "sticker_haiti", "HN": "sticker_honduras",
    "JM": "sticker_jamaica", "MX": "sticker_mexico", "NI": "sticker_nicaragua",
    "PA": "sticker_panama", "PY": "sticker_paraguay", "PE": "sticker_peru",
    "KN": "sticker_saint_kitts_and_nevis", "LC": "sticker_saint_lucia",
    "VC": "sticker_saint_vincent_and_the_grenadines", "TT": "sticker_trinidad_and_tobago",
    "UY": "sticker_uruguay", "US": "sticker_united_states", "VE": "sticker_venezuela",
    "AU": "sticker_australia", "FJ": "sticker_fiji", "KI": "sticker_kiribati",
    "MH": "sticker_marshall_islands", "FM": "sticker_micronesia", "NR": "sticker_nauru",
    "NZ": "sticker_new_zealand", "PG": "sticker_papua_new_guinea", "WS": "sticker_samoa",
    "SB": "sticker_solomon_islands", "TO": "sticker_tonga", "TV": "sticker_tuvalu",
    "VU": "sticker_vanuatu", "PW": "sticker_palau",
    "SR": "sticker_suriname", "GF": "sticker_french_guiana", "MQ": "sticker_martinique",
    "AW": "sticker_aruba", "BQ": "sticker_bonaire", "CW": "sticker_curaçao",
    "PR": "sticker_puerto_rico", "BL": "sticker_saint_barthélemy", "MF": "sticker_saint_martin",
    "VI": "sticker_us_virgin_islands", "PM": "sticker_saint_pierre_and_miquelon",
    "BM": "sticker_bermuda", "KY": "sticker_cayman_islands",
    "NF": "sticker_norfolk_island", "PF": "sticker_polynesia_french", "GU": "sticker_guam",
    "AS": "sticker_american_samoa", "NC": "sticker_new_caledonia",
]

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
        if let assetName = worldStickerAssetByCountryCode[country.countryCode] {
            // Obrót WRÓCIŁ (03.09.2026, user: "żeby nie wyglądało jak od
            // linijki") — ale tym razem z `scaleEffect` lekko pomniejszającym
            // PRZED obrotem, żeby rotowany prostokąt zmieścił się z powrotem
            // w oryginalnych granicach (stąd nie wystaje poza komórkę siatki
            // jak poprzednio — to dokładnie ten sam bug co przy Francji,
            // tylko naprawiony matematycznie zamiast przez usunięcie obrotu).
            VStack(spacing: 2) {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                if !dateText.isEmpty {
                    Text(dateText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
            }
            .padding(6)
            .scaleEffect(0.9)
            .rotationEffect(.degrees(rotationDegrees))
        } else {
            oldStyleStamp
        }
    }

    private var oldStyleStamp: some View {
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
