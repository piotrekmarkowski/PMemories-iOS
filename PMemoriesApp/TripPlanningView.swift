import SwiftUI
import SwiftData
import MapKit

/// "Trip Planning / My Next Journey" — Etap 1 (`Docs/TODO.md`, P1 z analizy
/// konkurencji 10.08.2026), model zrewidowany 11.08.2026 na podstawie
/// przemyślanego feedbacku usera (patrz `PlannedTripPersistence.swift` po
/// pełne uzasadnienie: Accommodation jako jeden uniwersalny element, pary
/// dat pobytu, Places to visit). Appka dotąd była silna TYLKO "po podróży"
/// (Travel Map wykrywa trasę WSTECZNIE, z EXIF/GPS zdjęć które już
/// istnieją) — zero wsparcia "przed". Świadomie NIE pełny planer budżetu/
/// waluty/rezerwacji — to by kopiowało TripMapper 1:1, PMemories nie musi
/// tego wygrywać. Kluczowa unikalna klamra: "Convert Trip → Memory"
/// (`PlannedTrip.asTripStops`) — łączy ten moduł z tym co appka już robi
/// najlepiej, zamiast być osobnym dodatkiem.
struct TripPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannedTrip.createdAt, order: .reverse) private var plannedTrips: [PlannedTrip]
    @Binding var selectedTab: MainTab
    @Binding var pendingTravelMapPrefillStops: [TripStop]?

    @State private var editingTrip: PlannedTrip?

    var body: some View {
        NavigationStack {
            Group {
                if plannedTrips.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .tabSkinBackground()
            // BUG znaleziony 11.08.2026 (user: "napis Planowanie podróży
            // nie jest za bardzo widoczny na tej skórce") — ten sam,
            // wcześniej już potwierdzony problem co "Travel Map" 02.08.2026:
            // `.navigationTitle` nie reaguje na kolor skórki w tle (system
            // zawsze rysuje go domyślnym kolorem trybu jasny/ciemny, nie
            // wg zdjęcia). Ten sam sprawdzony fix: pusty systemowy tytuł +
            // WŁASNY tekst jako pierwszy wiersz listy (`skinAwareHeading()`,
            // pełna kontrola koloru) — patrz `list` niżej.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: addTrip) {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $editingTrip) { trip in
                // Nowo utworzona (pusta) podróż startuje wprost w trybie
                // edycji — 11.08.2026, user: "podgląd tego co się ma
                // zapisane" ma sens tylko gdy JEST już coś zapisane.
                let isBlank = trip.title.trimmingCharacters(in: .whitespaces).isEmpty
                    && (trip.stops ?? []).allSatisfy { $0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }
                PlannedTripDetailView(
                    trip: trip, selectedTab: $selectedTab,
                    pendingTravelMapPrefillStops: $pendingTravelMapPrefillStops,
                    startInEditMode: isBlank
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 40))
                .foregroundStyle(Palette.heroGradient)
            VStack(spacing: 12) {
                Text("Plan your next journey")
                    .font(.title3.bold())
                Text("Add cities, dates, flights and hotel notes before you go — after the trip, convert it straight into a Memory.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .skinAwareHeading()
            Button(action: addTrip) {
                Label("New Trip", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Palette.heroGradient, in: Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            // Inny tekst niż etykieta zakładki (11.08.2026, user: "w
            // nagłówku powinno być zaplanowane podróże czy coś w tym
            // stylu") — ten sam wzorzec co "Library" (zakładka) / "Play
            // Memories" (nagłówek listy) w `LibraryView`: nazwa zakładki
            // opisuje SEKCJĘ, nagłówek nad listą opisuje ZAWARTOŚĆ.
            Text(L("Planned Trips"))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .skinAwareHeading()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            ForEach(plannedTrips) { trip in
                Button {
                    editingTrip = trip
                } label: {
                    row(for: trip)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indices in
                for index in indices { modelContext.delete(plannedTrips[index]) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(for trip: PlannedTrip) -> some View {
        let sortedStops = (trip.stops ?? []).sorted(by: { $0.order < $1.order })
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(rowFlags(for: sortedStops))
                Text(trip.title.isEmpty ? L("New Trip") : trip.title)
                    .font(.system(size: 16, weight: .semibold))
            }
            let cities = sortedStops.map(\.cityName).filter { !$0.isEmpty }
            if !cities.isEmpty {
                Text(cities.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Wzbogacone 11.08.2026 (user's mockup: data + ikony transportu +
            // nocleg w jednym rzędzie pod trasą) — te same emoji co reszta
            // appki (`TransportMode.emoji`/`AccommodationType.emoji`), zero
            // nowych symboli do nauczenia się.
            HStack(spacing: 6) {
                // Konkretny zakres dat, nie tylko czas trwania (11.08.2026,
                // user: "chyba jeszcze data by się przydała" po zobaczeniu
                // samego "7 nocy · 8 dni" bez informacji OD KIEDY).
                if let dateRangeText = trip.dateRangeText {
                    Text(dateRangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·").font(.caption2).foregroundStyle(.secondary)
                }
                if let nightsAndDaysText = trip.nightsAndDaysText {
                    Text(nightsAndDaysText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(rowTransportEmojis(for: sortedStops), id: \.self) { emoji in
                    Text(emoji).font(.caption2)
                }
                if sortedStops.contains(where: { $0.accommodationRawValue != nil }) {
                    Text("🛏️").font(.caption2)
                }
            }
        }
        .padding(.vertical, 4)
        // BUG znaleziony 11.08.2026 (user: "dosłownie nic" po tapnięciu w
        // kartę na liście) — `VStack` bez rozciągnięcia na pełną szerokość
        // i bez `.contentShape` hit-testuje TYLKO faktyczny rozmiar tekstu
        // (lewa, wąska część), nie całą widoczną białą kartę systemowego
        // wiersza `List` — dotknięcie poza literami tytułu/podtytułu trafiało
        // w martwe pole. Oba fixy razem: pełna szerokość + jawny kształt
        // hit-testu na całym obszarze.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func rowFlags(for sortedStops: [PlannedStop]) -> String {
        var seen = Set<String>()
        let codes = sortedStops.compactMap(\.countryCode).filter { seen.insert($0).inserted }
        return codes.map { CityGeocoder.flagEmoji(countryCode: $0) }.joined()
    }

    private func rowTransportEmojis(for sortedStops: [PlannedStop]) -> [String] {
        var seen = Set<TransportMode>()
        return sortedStops.dropFirst()
            .compactMap { TransportMode(rawValue: $0.transportRawValue) }
            .filter { seen.insert($0).inserted }
            .map(\.emoji)
    }

    /// Dwa puste przystanki na start — ten sam wzorzec co
    /// `TravelMapView`'s `stops: [TripStop] = [TripStop(), TripStop()]`
    /// (para "skąd"/"dokąd" gotowa do wypełnienia, zero pustego ekranu).
    ///
    /// BUG znaleziony 11.08.2026 (user: "nie możemy edytować nowej
    /// podróży") — `modelContext.insert(trip)` (zmienia `plannedTrips`,
    /// przełączając `Group` z `emptyState` na `list` przy PIERWSZEJ
    /// podróży) i `editingTrip = trip` (odpala `.navigationDestination`)
    /// w TEJ SAMEJ synchronicznej klatce: SwiftUI gubi się, gdy struktura
    /// widoku pod `NavigationStack` zmienia się w tym samym cyklu co próba
    /// wepchnięcia nowego celu nawigacji — nawigacja cicho nie działa (bez
    /// crasha). Fix: `editingTrip` ustawiane w NASTĘPNYM cyklu (`DispatchQueue.
    /// main.async`), żeby przełączenie `emptyState`→`list` zdążyło się
    /// najpierw w pełni odłożyć.
    private func addTrip() {
        let stopA = PlannedStop(cityName: "", order: 0)
        let stopB = PlannedStop(cityName: "", order: 1)
        let trip = PlannedTrip(title: "", stops: [stopA, stopB])
        modelContext.insert(trip)
        DispatchQueue.main.async {
            editingTrip = trip
        }
    }
}

/// Ekran zapisanej podróży — DWA tryby zamiast jednego formularza
/// (11.08.2026, user: "nie mogę edytować stworzonej podróży... do tego
/// powinien być normalny podgląd tego co się ma zapisane, edycja wygląda
/// jak ekran który wypełniamy na początku, podgląd powinien wyglądać ładnie
/// przejrzyście z tymi informacjami które mamy wpisane"). `isEditing ==
/// false` → `summaryView` (karty per przystanek, tylko do odczytu, "✏️" w
/// pasku wchodzi w edycję). `true` → dotychczasowy formularz wypełniania
/// (`editForm`, bez zmian w mechanice). Nowo utworzona pusta podróż
/// startuje wprost w `editForm` (`startInEditMode`, liczone przez
/// `TripPlanningView` z zawartości triposu) — podgląd pustego formularza
/// nie miałby sensu.
private struct PlannedTripDetailView: View {
    @Bindable var trip: PlannedTrip
    @Binding var selectedTab: MainTab
    @Binding var pendingTravelMapPrefillStops: [TripStop]?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing: Bool
    @State private var isShowingConvertConfirm = false
    /// Link do udostępnienia — wygenerowany LENIWIE, dopiero przy tapnięciu
    /// (12.08.2026, user: "share ma przejść i się zapisywać w appce od razu
    /// w zaplanowanych, jak się otworzy link"). Wymaga wywołania sieciowego
    /// (`ShareLinkService.createShareLink`), więc nie da się tego zrobić
    /// wewnątrz `Transferable` samego `TripTransferDTO` — Apple oznaczyło
    /// asynchroniczny wariant `ProxyRepresentation` jako `deprecated` od
    /// iOS 17 (sprawdzone w kompilatorze, nie zgadywane). Cache'owany po
    /// pierwszym wygenerowaniu — kolejne tapnięcia Share tej samej podróży
    /// nie tworzą nowego linku za każdym razem.
    @State private var shareLinkURL: URL?
    @State private var isPreparingShareLink = false
    @State private var shareLinkError: String?
    /// Okno udostępniania otwiera się SAMO gdy link jest gotowy (17.08.2026)
    /// — TEN SAM bug znaleziony 13.08.2026 w `TravelPassportView` (user:
    /// "za drugim razem działa"): zamiana `Button` → `ShareLink` PO
    /// wygenerowaniu linku tylko PRZYGOTOWUJE go, nie otwiera automatycznie.
    /// Teraz zgłoszone też tutaj (narzeczona usera: "musi kliknąć 2x").
    @State private var isShowingShareSheet = false
    /// PULL ręcznego odświeżenia współdzielonej podróży (16.08.2026) —
    /// patrz `pullLatestSharedVersion`.
    @State private var isPullingSharedUpdate = false

    init(
        trip: PlannedTrip, selectedTab: Binding<MainTab>,
        pendingTravelMapPrefillStops: Binding<[TripStop]?>, startInEditMode: Bool
    ) {
        self.trip = trip
        self._selectedTab = selectedTab
        self._pendingTravelMapPrefillStops = pendingTravelMapPrefillStops
        self._isEditing = State(initialValue: startInEditMode)
    }

    private var sortedStops: [PlannedStop] {
        (trip.stops ?? []).sorted { $0.order < $1.order }
    }

    private var hasAnyContent: Bool {
        !sortedStops.allSatisfy { $0.cityName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                summaryView
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Automatyczny PULL przy wejściu w podróż (16.08.2026, user: "nie
        // da się zrobić żeby bez odświeżania się to zmieniało tylko w
        // momencie jak otworzymy apkę?") — `.task` odpala się za każdym
        // wejściem w ten ekran (nowe pchnięcie w `NavigationStack`), więc
        // "otwieram appkę i wchodzę w podróż" samo ściąga najnowszą wersję,
        // bez tapnięcia 🔄. Przycisk 🔄 ZOSTAJE jako dodatkowa opcja gdy
        // user chce sprawdzić w trakcie oglądania (`.task` odpala się raz
        // na wejście, nie w pętli). Pominięte podczas `isEditing` — nie
        // chcemy nadpisać zdalną wersją czyichś niezapisanych zmian w
        // trakcie edycji.
        .task {
            if !isEditing {
                await pullLatestSharedVersion()
            }
        }
        // Link już GOTOWY → tapnięcie otwiera okno OD RAZU (17.08.2026,
        // patrz `isShowingShareSheet`).
        .onChange(of: shareLinkURL) { _, newValue in
            if newValue != nil { isShowingShareSheet = true }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let shareLinkURL {
                ActivityShareSheet(items: [shareLinkURL])
            }
        }
        .alert(
            "Convert to Memory?",
            isPresented: $isShowingConvertConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Convert") { convert() }
        } message: {
            Text("This sends your planned stops to Travel Map and removes them from Trip Planning.")
        }
        .alert(L("Couldn't create share link"), isPresented: Binding(
            get: { shareLinkError != nil }, set: { if !$0 { shareLinkError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(shareLinkError ?? "")
        }
    }

    /// Flaga(i) kraju w tytule (11.08.2026, user: "Romania 🇷🇴") — z pierwszego
    /// przystanku który już ma rozwiązany kod kraju (`CitySearchCompleter`
    /// ustawia go dopiero PO wybraniu podpowiedzi, więc świeżo dopisane
    /// miasto bez wyboru z listy może go jeszcze nie mieć — stąd `first`,
    /// zero zgadywania flagi z samej nazwy tekstowej).
    private var navigationTitleText: String {
        guard !trip.title.isEmpty else { return L("New Trip") }
        guard let code = sortedStops.compactMap(\.countryCode).first else { return trip.title }
        return "\(trip.title) \(CityGeocoder.flagEmoji(countryCode: code))"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .confirmationAction) {
                // PUSH do serwera (16.08.2026) — TYLKO gdy podróż jest już
                // współdzielona (`trip.shareID`), no-op inaczej. Patrz
                // `pushShareUpdateIfNeeded`.
                Button(L("Done")) {
                    isEditing = false
                    pushShareUpdateIfNeeded()
                }
            }
            // Uchwyty przeciągania (☰) w `PlannedStopRow` pokazują się
            // tylko w trybie edycji SwiftUI `List` — `EditButton()` sam
            // zarządza otaczającym `\.editMode`, nic dodatkowego do
            // spinania (12.08.2026).
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        } else {
            // Wysyłanie planu do kogoś kto leci z Tobą (11.08.2026, link
            // 12.08.2026) — żeby druga osoba nie musiała wpisywać tej samej
            // trasy od zera. Link (nie plik) działa w KAŻDEJ appce z Share
            // Sheet, łącznie z Messengerem/WhatsAppem (które nie przyjmują
            // niestandardowych plików) — po otwarciu importuje podróż
            // bezpośrednio przez Universal Link.
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Ręczne PULL odświeżenie (16.08.2026) — widoczne TYLKO gdy
                // podróż jest już współdzielona (`shareID`), żeby nie mylić
                // z jakimkolwiek innym odświeżaniem. Brak auto-polling w tle
                // celowo — user sam decyduje kiedy sprawdzić najnowszą wersję
                // drugiej strony.
                if trip.shareID != nil {
                    Button {
                        Task { await pullLatestSharedVersion() }
                    } label: {
                        if isPullingSharedUpdate {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isPullingSharedUpdate)
                    .accessibilityLabel(L("Refresh shared trip"))
                }
                // JEDEN stały przycisk (17.08.2026, patrz `isShowingShareSheet`)
                // zamiast Button→ShareLink zamiany — okno otwiera się samo
                // przez `.onChange(of: shareLinkURL)`/`.sheet` niżej, zero
                // drugiego tapnięcia.
                Button {
                    prepareShareLink()
                } label: {
                    if isPreparingShareLink {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(!hasAnyContent || isPreparingShareLink)
                Button {
                    // Link ewentualnie wygenerowany PRZED tą edycją byłby
                    // przestarzały (stare miasta/daty) — wyczyszczony, żeby
                    // kolejne tapnięcie Share zbudowało świeży.
                    shareLinkURL = nil
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L("Edit trip"))
            }
        }
    }

    // MARK: - Podgląd

    /// Przebudowane 11.08.2026 po feedbacku usera na żywo ("ten ekran jest
    /// teraz trochę przypadkowy i nie daje poczucia że oglądamy zaplanowaną
    /// podróż... wyrzuciłbym albo mocno ograniczył to wielkie rozmyte tło,
    /// dodałbym mapę podróży jako główny element wizualny i zrobił prawdziwy
    /// timeline"). Bez `.tabSkinBackground()` na tym konkretnym ekranie
    /// (świadomy wyjątek od reguły "każda zakładka ma skórkę" — user chce
    /// TU czystą, czytelną hierarchię, nie klimat). Kolejność: daty →
    /// statyczna mapa trasy → timeline przystanków z łącznikami transportu
    /// → Convert jako główny CTA na samym dole (user: "nie powinien pojawiać
    /// się tak wysoko jak teraz").
    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !trip.tripDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(trip.tripDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let tripDateSummary {
                    Label(tripDateSummary, systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                }
                RouteMapCard(stops: sortedStops)
                timelineSection
                // Budget PO trasie, nie przed nią (17.08.2026, ten sam duch
                // co przebudowa `editForm` — "gdzie jadę" przed "ile
                // wydam").
                budgetSummarySection
                convertSection
            }
            .padding(20)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Itinerary"), systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(sortedStops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    TransportConnector(
                        mode: TransportMode(rawValue: stop.transportRawValue) ?? .plane,
                        departureTime: stop.transportDepartureTime, arrivalTime: stop.transportArrivalTime
                    )
                }
                StopSummaryCard(stop: stop, isFirst: index == 0)
            }
        }
    }

    /// `nightsAndDaysText` wymaga OBU dat — tu pokazujemy coś sensownego
    /// nawet gdy user ustawił tylko jedną (zero zgadywania drugiej).
    /// Zakres dat ("16–23 sie") + czas trwania razem (11.08.2026, user:
    /// "chyba jeszcze data by się przydała") — samo "7 nocy · 8 dni" nie
    /// mówiło OD KIEDY.
    private var tripDateSummary: String? {
        if let range = trip.dateRangeText, let duration = trip.nightsAndDaysText {
            return "\(range) · \(duration)"
        }
        if let text = trip.nightsAndDaysText { return text }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if let start = trip.startDate {
            return String(format: L("From %@"), formatter.string(from: start))
        }
        if let end = trip.endDate {
            return String(format: L("Until %@"), formatter.string(from: end))
        }
        return nil
    }

    /// Szacowany budżet (12.08.2026, user: "można dodać koszty podróży i
    /// noclegu, wtedy jeśli ktoś będzie chciał, to może komuś polecić") —
    /// widoczne w podglądzie TYLKO gdy user wypełnił choć jedno pole kosztu
    /// (`PlannedTrip.totalEstimatedCost`), zero pustej karty "$0".
    @ViewBuilder
    private var budgetSummarySection: some View {
        if let total = trip.totalEstimatedCost {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("Estimated budget"), systemImage: "dollarsign.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(PlannedTrip.formattedCost(total, currencyCode: trip.currencyCode))
                    .font(.title3.bold())
            }
        }
    }

    private var convertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isShowingConvertConfirm = true
            } label: {
                // Etykieta zmienia się PO podróży (11.08.2026, user:
                // "kiedy podróż zostanie zakończona, zmieniłbym to
                // dynamicznie na Create Memory from this trip") —
                // `PlannedTrip.looksCompleted`, zero zgadywania gdy
                // appka nie zna żadnej daty (zostaje "Convert").
                if trip.looksCompleted {
                    Label("✨ Create Memory from this trip", systemImage: "sparkles")
                } else {
                    Label("Convert Trip → Memory", systemImage: "film.stack")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAnyContent)
            Text("Sends these stops to Travel Map to build your route, then removes this plan — your trip lives on there.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Edycja (dotychczasowy formularz wypełniania, bez zmian w mechanice)

    /// Waluta CAŁEJ podróży + koszty. Loty WYDZIELONE (12.08.2026, user:
    /// "koszty przelotów musimy dodać na górze, żeby się sumował") —
    /// osobna linijka zamiast ginąć w ogólnym worku "inne koszty". Przełącznik
    /// "All-inclusive" (user: "chyba że to wycieczka all in z biura podróży,
    /// wtedy możemy wpisać całą kwotę tam") ukrywa loty/nocleg-per-przystanek
    /// z sumy — jedna kwota już je zawiera. Nocleg per przystanek ma własne
    /// pole PRZY konkretnym przystanku (sekcja Accommodation), bo tam już
    /// jest kontekst noclegu.
    private var budgetSection: some View {
        Section(L("Budget")) {
            Picker(L("Currency"), selection: $trip.currencyCode) {
                ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            Toggle(L("All-inclusive package"), isOn: $trip.isWholePackage)
            if trip.isWholePackage {
                OptionalCostField(
                    addButtonLabel: L("Add package cost"), currencyCode: trip.currencyCode,
                    amount: $trip.estimatedCostAmount
                )
                .font(.caption)
                Text(L("Already includes flights and accommodation — don't add them separately."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                OptionalCostField(
                    addButtonLabel: L("Add flight costs"), currencyCode: trip.currencyCode,
                    amount: $trip.flightCostAmount
                )
                .font(.caption)
                OptionalCostField(
                    addButtonLabel: L("Add other costs (transport, activities)"), currencyCode: trip.currencyCode,
                    amount: $trip.estimatedCostAmount
                )
                .font(.caption)
            }
            if let total = trip.totalEstimatedCost {
                Text("\(L("Estimated total")): \(PlannedTrip.formattedCost(total, currencyCode: trip.currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Kolejność sekcji (17.08.2026, przebudowa po feedbacku usera: "kolejność
    /// informacji jest odwrócona... pierwsza myśl usera powinna być dokąd
    /// jadę, nie ile wydam") — Podstawy → Daty → Trasa → **Budget na końcu**
    /// (był drugi, zaraz po tytule). Sama trasa (`PlannedStopRow`) zostaje
    /// JEDNYM ciągłym `ForEach` w jednej `Section` (nie osobna `Section` per
    /// przystanek) — SwiftUI `List` nie przełącza drag-reorderu między
    /// osobnymi `Section`ami tak samo prosto jak w jednym `ForEach`, a
    /// `.onMove`/`.onDelete` na przystankach to funkcja warta zachowania
    /// bez ryzyka.
    private var editForm: some View {
        List {
            Section {
                TextField(L("Trip title"), text: $trip.title)
                TextField(L("Description"), text: $trip.tripDescription, axis: .vertical)
                    .font(.caption)
                    .lineLimit(1...4)
            }

            Section(L("Trip dates")) {
                OptionalDateField(
                    addButtonLabel: L("Add start date"), pickerLabel: L("Start date"), date: $trip.startDate
                )
                OptionalDateField(
                    addButtonLabel: L("Add end date"), pickerLabel: L("End date"), date: $trip.endDate
                )
                if let nightsAndDaysText = trip.nightsAndDaysText {
                    Text(nightsAndDaysText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(Array(sortedStops.enumerated()), id: \.element.id) { index, stop in
                    PlannedStopRow(
                        stop: stop, stepIndex: index + 1,
                        nextStop: index + 1 < sortedStops.count ? sortedStops[index + 1] : nil
                    )
                }
                .onDelete(perform: deleteStops)
                .onMove(perform: moveStops)

                Button(action: addStop) {
                    Label("Add stop", systemImage: "plus.circle")
                }
            }

            budgetSection
        }
    }

    /// Przeciąganie przystanków (12.08.2026, wcześniej dziś tylko dodawanie
    /// na końcu + usuwanie) — `EditButton()` w pasku (widoczny tylko w
    /// trybie edycji) pokazuje uchwyty ☰, bo wiersze `PlannedStopRow` mają
    /// za dużo własnych interaktywnych elementów (pola tekstowe/menu) żeby
    /// przeciąganie działało bez wyraźnego trybu.
    private func moveStops(from source: IndexSet, to destination: Int) {
        var stops = sortedStops
        stops.move(fromOffsets: source, toOffset: destination)
        for (index, stop) in stops.enumerated() {
            stop.order = index
        }
    }

    private func addStop() {
        let stop = PlannedStop(cityName: "", order: sortedStops.count)
        modelContext.insert(stop)
        trip.stops = (trip.stops ?? []) + [stop]
    }

    private func deleteStops(at offsets: IndexSet) {
        let stops = sortedStops
        for offset in offsets {
            let stop = stops[offset]
            trip.stops?.removeAll { $0.id == stop.id }
            modelContext.delete(stop)
        }
    }

    private func convert() {
        let prefill = trip.asTripStops
        dismiss()
        pendingTravelMapPrefillStops = prefill
        modelContext.delete(trip)
        selectedTab = .travel
    }

    /// Wysyła podróż na serwer i zamienia otrzymane ID w Universal Link
    /// (12.08.2026) — patrz komentarz przy `shareLinkURL`. Gdy podróż JUŻ MA
    /// `shareID` (16.08.2026 — była udostępniona wcześniej, w tej albo
    /// poprzedniej sesji), link budujemy z NIEGO zamiast tworzyć drugi,
    /// równoległy rekord na serwerze pod nowym ID — inaczej PUSH/PULL
    /// synchronizacji zaczęłyby celować w różne rekordy po dwóch stronach.
    private func prepareShareLink() {
        // Link już gotowy z poprzedniego tapnięcia w TEJ sesji widoku —
        // otwórz OD RAZU (17.08.2026). Bez tego druga i kolejne tapnięcia
        // nie otwierałyby okna: `.onChange(of: shareLinkURL)` reaguje
        // tylko na ZMIANĘ wartości, a tu wartość zostaje ta sama.
        if shareLinkURL != nil {
            isShowingShareSheet = true
            return
        }
        if let shareID = trip.shareID {
            shareLinkURL = ShareLinkService.tripURL(id: shareID)
            return
        }
        isPreparingShareLink = true
        Task {
            defer { isPreparingShareLink = false }
            do {
                let url = try await ShareLinkService.createShareLink(for: trip.transferDTO)
                shareLinkURL = url
                trip.shareID = url.lastPathComponent
            } catch {
                shareLinkError = error.localizedDescription
            }
        }
    }

    /// PUSH edycji do serwera (16.08.2026, żywa synchronizacja) — wołane po
    /// "Done", TYLKO gdy podróż jest już współdzielona (`shareID`). Ciche
    /// niepowodzenie (np. brak sieci) — user i tak może spróbować ponownie
    /// przy następnej edycji albo ręcznym Refresh drugiej strony; appka nie
    /// blokuje UI na wywołanie sieciowe przy zwykłym zamknięciu edycji.
    private func pushShareUpdateIfNeeded() {
        guard let shareID = trip.shareID else { return }
        let dto = trip.transferDTO
        Task {
            do {
                try await ShareLinkService.updateSharedTrip(id: shareID, dto: dto)
            } catch {
                print("⚠️ PMemories share sync: PUSH nie powiódł się (\(error))")
            }
        }
    }

    /// PULL najnowszej wersji z serwera (16.08.2026) — nadpisuje LOKALNĄ
    /// kopię "ostatnim zapisem" drugiej strony. Wołane ręcznie (przycisk
    /// Refresh w podglądzie) — świadomie bez automatycznego polling w tle,
    /// żeby appka nie strzelała do serwera bez powodu.
    private func pullLatestSharedVersion() async {
        guard let shareID = trip.shareID else { return }
        isPullingSharedUpdate = true
        defer { isPullingSharedUpdate = false }
        do {
            let dto = try await ShareLinkService.fetchTrip(id: shareID)
            trip.applyRemoteUpdate(dto, modelContext: modelContext)
        } catch {
            shareLinkError = error.localizedDescription
        }
    }
}

/// Karta pojedynczego przystanku w podglądzie (11.08.2026) — tylko do
/// odczytu, pokazuje WSZYSTKO co user wpisał w edycji (nocleg, daty pobytu,
/// notatki, miejsca do odwiedzenia) w zwartej, czytelnej formie zamiast
/// pustych pól formularza.
private struct StopSummaryCard: View {
    let stop: PlannedStop
    let isFirst: Bool

    private var accommodationType: AccommodationType? {
        stop.accommodationRawValue.flatMap(AccommodationType.init(rawValue:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            accommodationInfo
            datesInfo
            if !stop.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(stop.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            placesInfo
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(CityGeocoder.flagEmoji(countryCode: stop.countryCode))
            Text(stop.cityName.isEmpty ? L("Unnamed stop") : stop.cityName)
                .font(.headline)
            // "Start" na pierwszym przystanku (11.08.2026, user's mockup:
            // "Londyn / 📍 Start") — łącznik transportu (`TransportConnector`)
            // między kartami już pokazuje TRYB dojazdu do kolejnych, więc tu
            // nie duplikujemy ikony transportu jak w pierwszej wersji.
            if isFirst {
                Text(L("Start"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var accommodationInfo: some View {
        if let type = accommodationType {
            HStack(alignment: .top, spacing: 6) {
                Text(type.emoji)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.label)
                        .font(.caption.weight(.medium))
                    if let name = stop.accommodationName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let address = stop.accommodationAddress, !address.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(address)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let cost = stop.accommodationCostAmount, cost != 0 {
                        Text(PlannedTrip.formattedCost(cost, currencyCode: stop.trip?.currencyCode ?? Locale.current.currency?.identifier ?? "USD"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var datesInfo: some View {
        if let nights = stop.nights {
            Label(nightsText(nights), systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Grupowanie po dniu pobytu (12.08.2026, user: "place to visit
    /// rozdzielone na dni") — `nil` (bez przypisanego dnia) ląduje na
    /// końcu pod etykietą "Any day", nie miesza się z konkretnymi dniami.
    private var groupedPlaces: [(dayIndex: Int?, places: [PlaceToVisit])] {
        let sorted = (stop.placesToVisit ?? []).sorted { $0.order < $1.order }
        let grouped = Dictionary(grouping: sorted, by: \.dayIndex)
        return grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (l?, r?): return l < r
            case (nil, _): return false
            case (_, nil): return true
            }
        }.map { ($0, grouped[$0] ?? []) }
    }

    /// "Day 1 · 16 Aug" gdy znamy `checkInDate` (dokładna data), inaczej
    /// sam ordynał "Day 1" — dzień działa też bez dat, appka nic nie zgaduje.
    private func dayLabel(for dayIndex: Int) -> String {
        guard let checkInDate = stop.checkInDate,
              let date = Calendar.current.date(byAdding: .day, value: dayIndex - 1, to: checkInDate) else {
            return "\(L("Day")) \(dayIndex)"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return "\(L("Day")) \(dayIndex) · \(formatter.string(from: date))"
    }

    @ViewBuilder
    private var placesInfo: some View {
        if !(stop.placesToVisit ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groupedPlaces, id: \.dayIndex) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        if let dayIndex = group.dayIndex {
                            Text(dayLabel(for: dayIndex))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if groupedPlaces.count > 1 {
                            Text(L("Any day"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.places) { place in
                            PlaceCheckboxRow(place: place)
                        }
                    }
                }
            }
        }
    }
}

/// Wiersz z checkboxem do odznaczania w trakcie podróży (12.08.2026, user:
/// "kwadracik który będziemy odznaczać podczas podróży co zobaczyliśmy") —
/// tapnięcie przełącza `.visited` <-> `.wantToVisit` bezpośrednio, bez
/// wchodzenia w Menu (to zostaje w edytorze do USTAWIANIA priorytetu przed
/// podróżą, tu chodzi o szybkie odznaczenie W TRAKCIE). `PlaceToVisit` to
/// `@Model` (referencyjny, `@Observable` przez makro) — mutacja właściwości
/// bez `@Bindable` wystarcza, żeby widok się odświeżył.
private struct PlaceCheckboxRow: View {
    let place: PlaceToVisit

    private var isVisited: Bool {
        PlaceVisitStatus(rawValue: place.statusRawValue) == .visited
    }

    var body: some View {
        Button {
            place.statusRawValue = isVisited ? PlaceVisitStatus.wantToVisit.rawValue : PlaceVisitStatus.visited.rawValue
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isVisited ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isVisited ? Palette.blue : Color.secondary)
                Text(place.name)
                    .font(.caption)
                    .strikethrough(isVisited)
                    .foregroundStyle(isVisited ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Wspólny widok "tap żeby dodać datę / DatePicker + X żeby wyczyścić"
/// (11.08.2026) — wydzielony z Etapu 1's `plannedDateField`, bo teraz
/// potrzebny w CZTERECH miejscach (daty całej podróży + check-in/check-out
/// per przystanek) zamiast jednym. Zawsze opcjonalny — appka nigdy nie
/// wymusza dat (user: wybór ma zajmować sekundy, nie tworzyć tarcia).
private struct OptionalDateField: View {
    let addButtonLabel: String
    let pickerLabel: String
    @Binding var date: Date?
    /// Godzina pobytu dopisana 12.08.2026 (user: "skoro planujemy podróż,
    /// musi być o jakimś czasie") — domyślnie sam dzień (trip start/end),
    /// jawnie `[.date, .hourAndMinute]` przy check-in/check-out.
    var displayedComponents: DatePicker.Components = [.date]

    var body: some View {
        if let date {
            HStack {
                DatePicker(
                    pickerLabel,
                    selection: Binding(get: { date }, set: { self.date = $0 }),
                    displayedComponents: displayedComponents
                )
                .font(.caption)
                Button {
                    self.date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                date = Date()
            } label: {
                Label(addButtonLabel, systemImage: "calendar.badge.plus")
                    .font(.caption)
            }
        }
    }
}

/// Pole TYLKO na godzinę (12.08.2026) — dla czasu odjazdu/przyjazdu
/// transportu, gdzie appka już zna DZIEŃ z reszty planu i user wpisuje
/// wyłącznie porę (np. "14:00" dla rejsu/lotu), bez osobnej daty kalendarza.
private struct OptionalTimeField: View {
    let addButtonLabel: String
    let pickerLabel: String
    @Binding var time: Date?

    var body: some View {
        if let time {
            HStack {
                DatePicker(
                    pickerLabel,
                    selection: Binding(get: { time }, set: { self.time = $0 }),
                    displayedComponents: [.hourAndMinute]
                )
                .font(.caption)
                Button {
                    self.time = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                time = Date()
            } label: {
                Label(addButtonLabel, systemImage: "clock.badge.plus")
                    .font(.caption)
            }
        }
    }
}

/// Pole na kwotę w walucie podróży (12.08.2026, Budget) — sam symbol waluty
/// jako prefiks zamiast pola wyboru, `TextField` z klawiaturą numeryczną.
/// `@State` tekstowe pośrednie (nie bezpośredni `Binding<Double?>` do
/// `TextField`) — user może wpisywać przecinek zamiast kropki, appka
/// normalizuje przy parsowaniu zamiast blokować wpisywanie w locale które
/// go używa.
private struct OptionalCostField: View {
    let addButtonLabel: String
    let currencyCode: String
    @Binding var amount: Double?
    @State private var text: String = ""

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    var body: some View {
        if amount != nil {
            HStack {
                Text(currencySymbol)
                    .foregroundStyle(.secondary)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .onChange(of: text) { _, newValue in
                        amount = Double(newValue.replacingOccurrences(of: ",", with: "."))
                    }
                Button {
                    amount = nil
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .onAppear {
                if text.isEmpty, let amount, amount != 0 {
                    text = String(format: "%g", amount)
                }
            }
        } else {
            Button {
                amount = 0
                text = ""
            } label: {
                Label(addButtonLabel, systemImage: "dollarsign.circle")
                    .font(.caption)
            }
        }
    }
}

/// Wzorowane na `StopRow` w `TravelMapView.swift` — te same podpowiedzi
/// miast (`CitySearchCompleter`), bez części niepotrzebnych tu (miniaturka
/// markera/link do gotowego filmu — podróż jeszcze się nie odbyła).
/// `@Bindable` zamiast `@Binding`, bo `PlannedStop` to referencyjny
/// `@Model`, nie wartościowy `TripStop`.
///
/// Rozbite na osobne `@ViewBuilder` computed properties (11.08.2026) — po
/// dodaniu Accommodation/dat pobytu/Places to visit jeden wielki `VStack`
/// w `body` zaczął przekraczać limit czasu type-checkera Swifta (ten sam,
/// wielokrotnie potwierdzony dziś błąd co w `EditView.swift`/
/// `TravelMapView.swift`).
private struct PlannedStopRow: View {
    @Bindable var stop: PlannedStop
    /// Numer kroku w trasie, liczony OD 1 (17.08.2026, przebudowa: "kroki
    /// podróży" zamiast płaskiego formularza) — `isFirst` (poniżej) to tylko
    /// `stepIndex == 1`, trzymane jako osobny computed property dla
    /// czytelności zamiast przeliczać `== 1` w kilku miejscach.
    let stepIndex: Int
    /// Kolejny przystanek w trasie (18.08.2026, user: "departure time
    /// powinien być przy mieście startowym?") — używany WYŁĄCZNIE do
    /// edycji `nextStop.transportDepartureTime` Z TEGO wiersza (godzina
    /// odjazdu STĄD, do kolejnego miasta), bo appka historycznie trzyma
    /// czas odjazdu przy przystanku DOCELOWYM, nie źródłowym (patrz
    /// `PlannedTrip.departureTimeToday`: "transport DO drugiego
    /// przystanku"). User chce widzieć "kiedy stąd wylatuję" przy mieście
    /// z którego wylatuje, nie zagrzebane w wierszu docelowym razem z
    /// przyjazdem. `nil` dla ostatniego przystanku — nic stąd nie odjeżdża
    /// w ramach tej podróży.
    let nextStop: PlannedStop?
    @Environment(\.modelContext) private var modelContext
    @StateObject private var completer = CitySearchCompleter()
    @FocusState private var isFocused: Bool
    @State private var isApplyingSuggestion = false
    /// Ile dni pokazać w "Places to visit" (18.08.2026, przebudowa na
    /// grupowanie po dniach) — startuje z `maxDayCount` (z długości
    /// pobytu/istniejących przypisań), rośnie o 1 za każdym tapnięciem
    /// "Add Day". LOKALNY stan (nie persystowany) — "dzień" to WYŁĄCZNIE
    /// wartość `PlaceToVisit.dayIndex`, appka nie ma osobnej encji "Day" do
    /// zapisania pustego dnia bez żadnego miejsca; wracając na ten ekran
    /// widoczne dni to znowu te z `maxDayCount`, ewentualny pusty dzień
    /// dodany ponad to znika. Zainicjalizowane w `.onAppear`.
    @State private var visibleDayCount = 1

    private var isFirst: Bool { stepIndex == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            cityField
            suggestionsList
            transportTimesRow
            transportCostSection
            if !isFirst {
                // Nocleg/daty pobytu/miejsca do zobaczenia (17/18.08.2026,
                // user: "miejsce wylotu nie potrzebuje noclegu, przecież to
                // jest miejsce skąd zaczynamy naszą podróż" — a potem, o
                // Places to visit: "żeby zobaczyć lotnisko czy toaletę na
                // nim?") — ukryte dla PIERWSZEGO przystanku, ten sam duch
                // co transport wyżej (nic "do" niego nie dojeżdża, nikt go
                // nie "zwiedza" w sensie turystycznym). Pola były i tak
                // zawsze opcjonalne, ale samo ICH POKAZYWANIE sugerowało że
                // trzeba — dla miasta startowego to mylące/zbędne.
                accommodationSection
                stayDatesSection
                placesToVisitSection
            }
            notesField
        }
        .padding(.vertical, 4)
        .onAppear {
            visibleDayCount = maxDayCount
        }
    }

    /// Nagłówek "kroku" (17.08.2026, przebudowa formularza) — numer +
    /// sposób dotarcia widoczne NAJPIERW, zanim user w ogóle dojdzie do
    /// nazwy miasta. Dla pierwszego przystanku statyczne "🏁 Starting
    /// point" (bez transportu — nic "do" niego nie dojeżdża). Dla kolejnych
    /// — sam `transportPicker` PRZENIESIONY tutaj z dawnego miejsca w
    /// środku wiersza (ta sama logika/binding, tylko inna pozycja), żeby
    /// tryb transportu był pierwszą rzeczą jaką user widzi w kroku, nie
    /// czymś zagrzebanym niżej.
    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("\(stepIndex).")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if isFirst {
                Text("🏁 \(L("Starting point"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                transportPicker
            }
            Spacer()
        }
    }

    // "Destination" zamiast "Next city" (18.08.2026, user: "zamiast next
    // city możemy to nazwać inaczej?") — nagłówek nad polem (`headerRow`)
    // już pokazuje numer kroku + tryb transportu, więc samo pole może być
    // krótsze/prostsze, bez powtarzania "next".
    private var cityField: some View {
        TextField(isFirst ? L("Starting city") : L("Destination"), text: $stop.cityName)
            .focused($isFocused)
            .onChange(of: stop.cityName) { _, newValue in
                guard !isApplyingSuggestion else { return }
                stop.coordinate = nil
                completer.updateQuery(newValue)
            }
    }

    @ViewBuilder
    private var suggestionsList: some View {
        if stop.coordinate == nil && !completer.results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(completer.results.prefix(10).enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var transportPicker: some View {
        Picker(L("Transport"), selection: transportBinding) {
            ForEach(TransportMode.allCases) { mode in
                Text("\(mode.emoji) \(mode.label)").tag(mode)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }

    private var transportBinding: Binding<TransportMode> {
        Binding(
            get: { TransportMode(rawValue: stop.transportRawValue) ?? .plane },
            set: { stop.transportRawValue = $0.rawValue }
        )
    }

    /// Godziny odjazdu/przyjazdu (12.08.2026, user: "jak ktoś bierze
    /// cruise, nie ma czasu... musi być o jakimś czasie") — tylko GODZINA,
    /// appka zna dzień z reszty planu. Zawsze opcjonalne.
    ///
    /// Rozdzielone na dwie sekcje (18.08.2026, user: "departure time
    /// powinien być przy mieście startowym?") — Arrival zostaje przy TYM
    /// mieście (kiedy TU przylatuję, własne pole), Departure pokazuje się
    /// TEŻ w tym wierszu ale edytuje pole `nextStop` (kiedy STĄD wylatuję,
    /// do kolejnego miasta) — patrz komentarz przy `nextStop`. Jeden
    /// wspólny `HStack`, żeby oba pola (gdy oba dotyczą) zostały obok
    /// siebie jak dawniej, każde `@ViewBuilder` samo znika gdy nie dotyczy.
    @ViewBuilder
    private var transportTimesRow: some View {
        if !isFirst || nextStop != nil {
            HStack(spacing: 12) {
                if !isFirst {
                    OptionalTimeField(
                        addButtonLabel: L("Arrival time"), pickerLabel: L("Arrival time"),
                        time: $stop.transportArrivalTime
                    )
                }
                if let nextStop {
                    OptionalTimeField(
                        addButtonLabel: L("Departure time"), pickerLabel: L("Departure time"),
                        time: Binding(
                            get: { nextStop.transportDepartureTime },
                            set: { nextStop.transportDepartureTime = $0 }
                        )
                    )
                }
            }
        }
    }

    /// Koszt biletu NA TĘ trasę (18.08.2026, Budget — user pokazał realną
    /// notatkę z planowania Tajlandii z osobnymi kosztami biletów
    /// wewnętrznych per-etap). Ten sam `nextStop` binding co Departure time
    /// wyżej — widoczne obok siebie, bo w praktyce to ta sama decyzja
    /// ("lecę stąd, tyle to kosztuje").
    @ViewBuilder
    private var transportCostSection: some View {
        if let nextStop {
            OptionalCostField(
                addButtonLabel: L("Add transport cost"),
                currencyCode: stop.trip?.currencyCode ?? Locale.current.currency?.identifier ?? "USD",
                amount: Binding(
                    get: { nextStop.transportCostAmount },
                    set: { nextStop.transportCostAmount = $0 }
                )
            )
            .font(.caption)
        }
    }

    /// Accommodation jako JEDEN uniwersalny element (11.08.2026, user: "ja
    /// zrobiłbym to jako jeden uniwersalny element Accommodation, a dopiero
    /// wewnątrz user wybiera typ") — `nil` = pominięte, appka nigdy nie
    /// wymusza wyboru. Nazwa/adres widoczne dla WSZYSTKICH typów (nie tylko
    /// "Other" jak w pierwszej wersji, user: "adres i nazwa powinny być
    /// opcjonalne" — bez wyjątków), zawsze opcjonalne. Ukryte dla "My home"
    /// razem z resztą pól noclegu (`stayDatesSection` niżej) — nazwa/adres
    /// własnego domu nie mają sensu.
    ///
    /// "No accommodation" jako JAWNA, zawsze widoczna pierwsza pozycja menu
    /// (17.08.2026, przebudowa formularza) — zastępuje dawny warunkowy
    /// przycisk "Remove" (widoczny tylko PO wyborze) tą samą akcją, ale
    /// zawsze dostępną. Etykieta przycisku w stanie pustym też zmieniona z
    /// "Add accommodation" (sugerowało brakujący krok) na "No accommodation"
    /// (uczciwie opisuje faktyczny domyślny stan).
    private var accommodationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button {
                    stop.accommodationRawValue = nil
                    stop.accommodationName = nil
                    stop.accommodationAddress = nil
                } label: {
                    Label(L("No accommodation"), systemImage: "xmark.circle")
                }
                ForEach(AccommodationType.allCases) { type in
                    Button {
                        stop.accommodationRawValue = type.rawValue
                    } label: {
                        Text("\(type.emoji) \(type.label)")
                    }
                }
            } label: {
                if let type = currentAccommodationType {
                    Label("\(type.emoji) \(type.label)", systemImage: "chevron.up.chevron.down")
                        .font(.caption)
                } else {
                    Label(L("No accommodation"), systemImage: "bed.double")
                        .font(.caption)
                }
            }

            if currentAccommodationType != nil && currentAccommodationType != .home {
                TextField(
                    L("Accommodation name (optional)"),
                    text: Binding(get: { stop.accommodationName ?? "" }, set: { stop.accommodationName = $0 })
                )
                .font(.caption)
                TextField(
                    L("Address (optional)"),
                    text: Binding(get: { stop.accommodationAddress ?? "" }, set: { stop.accommodationAddress = $0 })
                )
                .font(.caption)
                // Koszt noclegu (12.08.2026, Budget) — waluta CAŁEJ podróży
                // (`stop.trip`), nie osobna per przystanek, żeby suma miała
                // sens bez przeliczania kursów.
                OptionalCostField(
                    addButtonLabel: L("Add accommodation cost"),
                    currencyCode: stop.trip?.currencyCode ?? Locale.current.currency?.identifier ?? "USD",
                    amount: $stop.accommodationCostAmount
                )
                .font(.caption)
            }
        }
    }

    private var currentAccommodationType: AccommodationType? {
        stop.accommodationRawValue.flatMap(AccommodationType.init(rawValue:))
    }

    /// Pary dat pobytu W TYM miejscu — ukryte całkowicie dla "My home"
    /// (11.08.2026, user chwalił dokładnie ten case: "at home i koniec",
    /// bez wymuszania dat które tam nie mają sensu).
    @ViewBuilder
    private var stayDatesSection: some View {
        if currentAccommodationType != .home {
            VStack(alignment: .leading, spacing: 4) {
                OptionalDateField(
                    addButtonLabel: L("Add check-in date"), pickerLabel: L("Check-in date"), date: $stop.checkInDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                OptionalDateField(
                    addButtonLabel: L("Add check-out date"), pickerLabel: L("Check-out date"), date: $stop.checkOutDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                if let nights = stop.nights {
                    Text(nightsText(nights))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Przebudowane na grupowanie po dniach (18.08.2026, user: "np. day 1,
    /// to to i to, później naciskamy wyświetla się day 2 i znowu dodajemy
    /// miejsca") — zamiast płaskiej listy z Menu wyboru dnia PRZY KAŻDYM
    /// miejscu osobno, jawne sekcje "Day N" z WŁASNYM polem dodawania pod
    /// każdą (dzień = w KTÓRĄ sekcję dodano, nie osobny wybór po fakcie).
    /// "Any day" na końcu jako fallback dla miejsc bez przypisanego dnia
    /// (stare dane sprzed tej zmiany, albo user świadomie pomija dzień).
    private var placesToVisitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Nagłówek dopisany 11.08.2026 (user: "nazwa 'miejsce' może być
            // trochę niejasna" — samo pole tekstowe bez etykiety sekcji nie
            // tłumaczyło do czego służy).
            Label(L("Places to visit"), systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(1...max(visibleDayCount, 1), id: \.self) { day in
                DayPlacesSection(
                    dayIndex: day,
                    places: placesForDay(day),
                    cityCoordinate: stop.coordinate,
                    onAdd: { name in addPlace(name: name, dayIndex: day) },
                    onDelete: deletePlace,
                    onMove: movePlace
                )
            }
            unassignedPlacesSection
            Button {
                visibleDayCount += 1
            } label: {
                Label("\(L("Add Day")) \(visibleDayCount + 1)", systemImage: "plus.circle")
                    .font(.caption)
            }
        }
    }

    private func placesForDay(_ day: Int) -> [PlaceToVisit] {
        (stop.placesToVisit ?? []).filter { $0.dayIndex == day }.sorted { $0.order < $1.order }
    }

    /// Miejsca bez przypisanego dnia — tylko gdy takie ISTNIEJĄ (stare dane
    /// sprzed przebudowy 18.08.2026, nowo dodawane miejsca zawsze mają
    /// dzień z sekcji do której trafiły). Bez własnego pola dodawania — to
    /// świadomie fallback na wyświetlanie, nie równoległa droga dodawania.
    @ViewBuilder
    private var unassignedPlacesSection: some View {
        let unassigned = (stop.placesToVisit ?? []).filter { $0.dayIndex == nil }.sorted { $0.order < $1.order }
        if !unassigned.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Any day"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(unassigned) { place in
                    PlaceToVisitRow(place: place, dayCount: visibleDayCount, onDelete: { deletePlace(place) }, onMove: movePlace)
                }
            }
        }
    }

    private var notesField: some View {
        TextField(L("Notes — flights, plans…"), text: $stop.notes, axis: .vertical)
            .font(.caption)
            .lineLimit(2...5)
    }

    /// Zakres dni na start ekranu (18.08.2026, uproszczone — user: "nie
    /// musimy mieć od razu całego tygodnia wyświetlonego, wystarczy jeden
    /// dzień z opcją dodania kolejnych"). Świadomie BEZ automatycznego
    /// rozwinięcia do długości pobytu (`stop.nights`) jak w pierwszej
    /// wersji — appka startuje zawsze od Day 1, user sam dokłada kolejne
    /// dni przyciskiem "Add Day" w tempie w jakim faktycznie planuje.
    /// Jedyny wyjątek: user już ma przypisane miejsca poza dniem 1 (np.
    /// wrócił do wcześniej wypełnionej podróży) — wtedy startowy zakres
    /// musi sięgać co najmniej tam, żeby nie ukryć istniejących danych.
    private var maxDayCount: Int {
        let fromExisting = (stop.placesToVisit ?? []).compactMap(\.dayIndex).max()
        return max(fromExisting ?? 0, 1)
    }

    private func addPlace(name: String, dayIndex: Int?) {
        let place = PlaceToVisit(name: name, order: (stop.placesToVisit ?? []).count, dayIndex: dayIndex)
        modelContext.insert(place)
        stop.placesToVisit = (stop.placesToVisit ?? []) + [place]
    }

    private func deletePlace(_ place: PlaceToVisit) {
        stop.placesToVisit?.removeAll { $0.id == place.id }
        modelContext.delete(place)
    }

    /// Przeniesienie na inny dzień (18.08.2026) — jedyny sposób na zmianę
    /// dnia PO dodaniu, teraz przez menu kontekstowe na wierszu zamiast
    /// dawnego, zawsze widocznego pillowego Menu (to ostatnie znikło razem
    /// z przebudową na jawne sekcje dni — dzień jest teraz WIDOCZNY przez
    /// samo miejsce w layoucie, nie musi być podpisany przy każdym wierszu).
    private func movePlace(_ place: PlaceToVisit, to dayIndex: Int?) {
        place.dayIndex = dayIndex
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        isApplyingSuggestion = true
        stop.cityName = suggestion.title
        isFocused = false
        completer.clear()
        Task {
            if let (coordinate, country, countryCode, localizedCityName) = await CitySearchCompleter.resolve(suggestion) {
                stop.coordinate = coordinate
                stop.country = country
                stop.countryCode = countryCode
                // Nadpisuje surowy tytuł podpowiedzi (w języku REGIONU
                // telefonu) nazwą w JĘZYKU APPKI, gdy geokodowanie się
                // powiedzie — patrz `CitySearchCompleter.resolve`.
                if let localizedCityName, !localizedCityName.isEmpty {
                    stop.cityName = localizedCityName
                }
            }
            isApplyingSuggestion = false
        }
    }
}

/// Jeden wiersz "Places to visit" — nazwa + status (Must see/Want to
/// visit/Visited, `Menu` z emoji) + usuwanie.
///
/// Dzień PRZENIESIONY z zawsze-widocznego Menu (12.08.2026) do menu
/// kontekstowego (18.08.2026, przebudowa na jawne sekcje "Day N") — dzień
/// jest teraz widoczny przez SAMO miejsce miejsca w layoucie (sekcja pod
/// którą leży), nie musi być podpisany przy każdym wierszu. Zmiana dnia PO
/// dodaniu wciąż możliwa (`onMove`), tylko rzadziej używana droga.
private struct PlaceToVisitRow: View {
    @Bindable var place: PlaceToVisit
    /// Ile dni do wyboru w menu kontekstowym "Move to" — patrz komentarz
    /// przy `PlannedStopRow.visibleDayCount`.
    let dayCount: Int
    let onDelete: () -> Void
    let onMove: (PlaceToVisit, Int?) -> Void

    private var status: PlaceVisitStatus {
        PlaceVisitStatus(rawValue: place.statusRawValue) ?? .wantToVisit
    }

    var body: some View {
        HStack {
            Menu {
                ForEach(PlaceVisitStatus.allCases) { candidate in
                    Button {
                        place.statusRawValue = candidate.rawValue
                    } label: {
                        Text("\(candidate.emoji) \(candidate.label)")
                    }
                }
            } label: {
                Text(status.emoji)
            }
            Text(place.name)
                .font(.caption)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(1...max(dayCount, 1), id: \.self) { day in
                Button("\(L("Move to")) \(L("Day")) \(day)") { onMove(place, day) }
            }
            Button(L("Move to Any day")) { onMove(place, nil) }
        }
    }
}

/// Sekcja jednego dnia w "Places to visit" (18.08.2026) — nagłówek "Day N",
/// lista miejsc TEGO dnia, i WŁASNE pole dodawania z podpowiedziami
/// (`PlaceSearchCompleter`, ten sam wzorzec podpowiedzi co pole miasta —
/// `Map(selection:)`/lista pod polem, tylko bez kroku rozwiązywania
/// współrzędnej, bo `PlaceToVisit` jej nie przechowuje). Tapnięcie
/// podpowiedzi OD RAZU dodaje miejsce (mniej dotknięć niż wpisz→zatwierdź).
private struct DayPlacesSection: View {
    let dayIndex: Int
    let places: [PlaceToVisit]
    let cityCoordinate: CLLocationCoordinate2D?
    let onAdd: (String) -> Void
    let onDelete: (PlaceToVisit) -> Void
    let onMove: (PlaceToVisit, Int?) -> Void

    @StateObject private var completer = PlaceSearchCompleter()
    @State private var newPlaceName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(L("Day")) \(dayIndex)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(places) { place in
                PlaceToVisitRow(place: place, dayCount: dayIndex, onDelete: { onDelete(place) }, onMove: onMove)
            }
            HStack {
                TextField(L("Add a place"), text: $newPlaceName)
                    .font(.caption)
                    .focused($isFocused)
                    .onChange(of: newPlaceName) { _, newValue in
                        completer.updateQuery(newValue)
                    }
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newPlaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completer.results.prefix(6).enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            select(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.caption)
            }
        }
        .onAppear {
            if let cityCoordinate {
                completer.setRegion(center: cityCoordinate)
            }
        }
    }

    private func add() {
        let trimmed = newPlaceName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        newPlaceName = ""
        completer.clear()
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        newPlaceName = suggestion.title
        add()
        isFocused = false
    }
}

/// Statyczny podgląd trasy (11.08.2026, user: "nawet statyczny podgląd
/// trasy byłby tutaj dużo bardziej wartościowy niż rozmyte zdjęcie") —
/// znaczniki tylko dla przystanków z ROZWIĄZANĄ lokalizacją
/// (`CitySearchCompleter`, po wybraniu podpowiedzi z listy — wpisanie
/// miasta bez wyboru nie ustawia współrzędnych, zero zgadywania). Znika
/// całkowicie gdy żaden przystanek nie ma współrzędnych, zamiast pokazywać
/// pustą/mylącą mapę. `interactionModes: []` — to KARTA podglądu w
/// przewijanym `ScrollView`, nie osobna nawigowalna mapa (ta już istnieje w
/// zakładce Travel Map).
private struct RouteMapCard: View {
    let stops: [PlannedStop]

    private var located: [PlannedStop] {
        stops.filter { $0.coordinate != nil }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        located.compactMap(\.coordinate)
    }

    private var region: MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 4),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        if let region {
            Map(initialPosition: .region(region), interactionModes: []) {
                ForEach(located) { stop in
                    if let coordinate = stop.coordinate {
                        Marker(stop.cityName, coordinate: coordinate)
                    }
                }
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Palette.blue, lineWidth: 3)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// Łącznik między kartami przystanków w timeline (11.08.2026, user's
/// mockup: "Londyn ↓ ✈️ Samolot ↓ Braszów") — mały pionowy kreseczka +
/// emoji trybu + etykieta, zamiast duplikować ikonę transportu wewnątrz
/// samej karty docelowego przystanku jak w pierwszej wersji podglądu.
private struct TransportConnector: View {
    let mode: TransportMode
    /// Godziny odjazdu/przyjazdu (12.08.2026, user: "musi być o jakimś
    /// czasie") — `nil` gdy user je pominął, zero zgadywania.
    let departureTime: Date?
    let arrivalTime: Date?

    private var timeText: String? {
        guard departureTime != nil || arrivalTime != nil else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let departure = departureTime.map { formatter.string(from: $0) } ?? "?"
        let arrival = arrivalTime.map { formatter.string(from: $0) } ?? "?"
        return "\(departure) → \(arrival)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 18)
            Text(mode.emoji)
            Text(mode.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let timeText {
                Text("· \(timeText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
    }
}
