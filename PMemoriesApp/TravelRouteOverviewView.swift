import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Statyczny przegląd całej trasy podróży — WSZYSTKIE przystanki i odcinki
/// widoczne NARAZ, swobodnie przeglądalne (przesuwanie/przybliżanie), w
/// odróżnieniu od `TravelMapAnimationView` (samogrający przelot — w danym
/// momencie widoczny tylko JEDEN odcinek/przystanek, overlay dodawany i
/// usuwany w locie).
///
/// 18.08.2026 — user po zobaczeniu mockupu "tapnij zdjęcie → zobacz
/// dystans/czas do poprzedniego": "mapę już mamy... trzeba to tam tylko
/// ładnie wpasować". Sprawdzone w kodzie że TAKIEJ mapy (wszystkie
/// przystanki+linie naraz, tapnięcie) jeszcze nie było — World Globe pokazuje
/// wszystkie miejsca ze WSZYSTKICH podróży bez linii tras, flythrough ma
/// linie ale tylko jedną naraz. Ten widok składa się z ISTNIEJĄCYCH
/// kawałków: `RouteProvider` (te same trasy/style linii co flythrough),
/// wzorzec niezawodnego tapnięcia na markerze z `WorldGlobeView`
/// (`Map(selection:)` + `.tag`, `.onTapGesture`/`Button` w `Annotation`
/// przegrywają z gestem mapy — udokumentowane tam 30.07.2026).
struct TravelRouteOverviewView: View {
    let trip: SavedTrip

    private struct Leg {
        let from: SavedStop
        let to: SavedStop
        let route: RouteResult
    }

    @State private var legs: [Leg] = []
    @State private var isLoadingLegs = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedStopID: PersistentIdentifier?
    @State private var hasSetInitialCamera = false
    /// Wysuwany dołem panel "Itinerary" (18.08.2026) — pokazany OD RAZU,
    /// bez wyzwalającego przycisku (ten sam duch co karty miejsc w Apple
    /// Maps/Find My — zawsze obecny, tylko zwijalny). `.interactiveDismissDisabled()`
    /// w `body` (nie tu) trzyma go zawsze widocznym choćby w najmniejszym stanie.
    @State private var isShowingItinerary = true
    /// JAWNY stan startowego rozmiaru panelu (18.08.2026, naprawa buga: user
    /// "wyskakuje cała na ekran") — bez `selection:` bindingu SwiftUI dobiera
    /// początkowy detent samo, co dawało nieprzewidywalny, za duży rozmiar.
    /// Jawne `.height(140)` jako wartość początkowa `@State` gwarantuje mały,
    /// przewidywalny start niezależnie od zawartości.
    @State private var itineraryDetent: PresentationDetent = .height(140)

    private var sortedStops: [SavedStop] {
        trip.stops.sorted { $0.order < $1.order }
    }

    private var selectedLeg: Leg? {
        guard let selectedStopID else { return nil }
        return legs.first { $0.to.persistentModelID == selectedStopID }
    }

    /// Suma czasu WSZYSTKICH odcinków (18.08.2026, pasek statystyk) —
    /// dostępna dopiero po `loadLegs()`, `0` przed tym (pasek statystyk
    /// pokazuje ten element warunkowo, patrz `statsBar`).
    private var totalTravelMinutes: Double {
        legs.reduce(0) { $0 + $1.route.durationMinutes }
    }

    /// Unikalne środki transportu użyte w trasie — pierwszy przystanek
    /// pomijany (nic "do" niego nie dojeżdża). Liczone RAZ, reużywane przez
    /// tekst i ikonę paska statystyk (`usedTransportModesText`/
    /// `transportsSummaryIcon`) — jedno źródło prawdy zamiast liczenia
    /// dwa razy.
    private var usedTransportModes: [TransportMode] {
        let modes = sortedStops.dropFirst().compactMap { TransportMode(rawValue: $0.transportRawValue) }
        var seen: [TransportMode] = []
        for mode in modes where !seen.contains(mode) { seen.append(mode) }
        return seen
    }

    /// Np. "Flight • Train • Car".
    private var usedTransportModesText: String {
        usedTransportModes.map(\.label).joined(separator: " • ")
    }

    /// Ikona paska statystyk (18.08.2026, naprawiony realny bug — user:
    /// "w rogu jeśli to jest pociąg dlaczego mamy samochodzik?") — była na
    /// SZTYWNO `car.fill` niezależnie od faktycznego trybu. Teraz: jeden
    /// tryb użyty w całej trasie → jego WŁASNA ikona, kilka różnych trybów
    /// → neutralna ikona "mieszanego" transportu (tekst obok i tak
    /// wymienia wszystkie z osobna).
    private var transportsSummaryIcon: String {
        guard usedTransportModes.count == 1, let mode = usedTransportModes.first else {
            return "arrow.triangle.swap"
        }
        switch mode {
        case .plane: return "airplane"
        case .train: return "tram.fill"
        case .car: return "car.fill"
        case .boat: return "ferry.fill"
        case .cruise: return "sailboat.fill"
        case .hiking: return "figure.hiking"
        }
    }

    /// Ikona pojazdu w POŁOWIE każdego odcinka, obrócona wg kierunku jazdy
    /// (18.08.2026, user po zobaczeniu referencji-mockupu z ikoną samolotu
    /// na trasie: "pełniejszy redesign"). Reużywa DOKŁADNIE ten sam
    /// mechanizm co żywy przelot (`TravelLiveMapView`) — `VehicleIconSet.
    /// resolve` (wybór asset-u right/left/top + kąt obrotu, już ustalona
    /// logika per pojazd) + `RouteProvider.bearing` (namiar geograficzny) —
    /// zero nowej logiki rotacji, tylko SwiftUI `.rotationEffect` zamiast
    /// `CGAffineTransform` z UIKit-owej wersji. Wędrówka pomijana (nie ma
    /// odpowiednika w `VehicleIconSet`, rysowana emoji gdzie indziej w
    /// appce, nie tutaj).
    private var vehicleIcons: [(id: Int, coordinate: CLLocationCoordinate2D, assetName: String, rotationDegrees: Double)] {
        legs.enumerated().compactMap { index, leg in
            let mode = TransportMode(rawValue: leg.to.transportRawValue) ?? .plane
            guard mode != .hiking else { return nil }
            let path = leg.route.path
            guard path.count >= 2 else { return nil }
            let midIndex = path.count / 2
            let coordinate = path[midIndex]
            let bearing = RouteProvider.bearing(
                from: path[max(0, midIndex - 1)],
                to: path[min(path.count - 1, midIndex + 1)]
            )
            let resolved = VehicleIconSet.resolve(transport: mode, bearing: bearing)
            return (index, coordinate, resolved.assetName, resolved.rotationDegrees)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            mapArea
        }
        .animation(.easeOut(duration: 0.2), value: selectedStopID)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLegs()
        }
        // Panel Itinerary (18.08.2026) — pokazany OD RAZU (`isShowingItinerary`
        // startuje `true`), `.presentationBackgroundInteraction` pozwala dalej
        // przesuwać mapę pod częściowo otwartym panelem (jak Apple Maps/Find
        // My), `.interactiveDismissDisabled()` żeby nie dało się go całkiem
        // zamknąć — tylko zwinąć do najmniejszego stanu.
        .sheet(isPresented: $isShowingItinerary) {
            itineraryContent
                .presentationDetents([.height(140), .medium, .large], selection: $itineraryDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .interactiveDismissDisabled()
        }
    }

    /// Pasek statystyk pod nagłówkiem (18.08.2026, z mockupu usera) —
    /// liczba przystanków, suma dystansu (reużywa JUŻ PERSYSTOWANY
    /// `trip.totalDistanceKm`, nie trzeba czekać na `legs`), suma czasu
    /// podróży (nowe, dopiero PO wczytaniu `legs`) i lista trybów transportu.
    private var statsBar: some View {
        HStack(alignment: .top, spacing: 0) {
            statItem(icon: "mappin.circle.fill", value: "\(sortedStops.count)", label: L("Destinations"))
            Spacer()
            statItem(
                icon: "arrow.left.and.right",
                value: "\(Int(trip.totalDistanceKm.rounded()).formatted()) km",
                label: L("Total distance")
            )
            Spacer()
            if !isLoadingLegs {
                statItem(icon: "clock", value: Self.totalDurationText(totalTravelMinutes), label: L("Total travel time"))
                Spacer()
            }
            statItem(icon: transportsSummaryIcon, value: usedTransportModesText, label: L("Transports"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedStopID) {
                // Etykieta NAPRZEMIENNIE góra/dół po indeksie przystanku
                // (18.08.2026, user chciał "inteligentne" rozstawienie
                // etykiet żeby się nie nakładały) — natywny SwiftUI `Map`
                // nie daje dostępu do współrzędnych EKRANOWYCH adnotacji,
                // więc pełne wykrywanie kolizji nie jest tu wykonalne bez
                // przejścia na UIKit-owy `MKMapView` (duża zmiana
                // architektury). Naprzemienność to pragmatyczny, tani
                // kompromis — realnie zmniejsza nakładanie się sąsiednich
                // etykiet na typowej, chronologicznej trasie.
                ForEach(Array(sortedStops.enumerated()), id: \.element.persistentModelID) { index, stop in
                    Annotation(stop.cityName, coordinate: stop.coordinate) {
                        RouteStopMarker(
                            stop: stop,
                            labelAbove: index % 2 == 1,
                            badge: index == 0 ? L("START") : (index == sortedStops.count - 1 ? L("FINISH") : nil)
                        )
                    }
                    .tag(stop.persistentModelID)
                }
                // Kropkowany ślad (18.08.2026) PRÓBOWANY i ODRZUCONY przez
                // usera — "jesteśmy na mapie, co te kropki pokazują nic,
                // wiesz dobrze jaką trasę wykonaliśmy więc ją narysuj
                // poprawnie". Wersja "wyraźna linia" POTEM też skrytykowana
                // jako "rysowanie trzylatka" (poszarpana/niewyraźna na
                // realnym terenie satelitarnym, zwłaszcza gdy dwa odcinki
                // (tam i z powrotem) nachodzą na siebie geograficznie).
                // Naprawa: HALO pod spodem (biała, szersza, półprzezroczysta
                // obwódka) + czysta kolorowa linia NA WIERZCHU — standardowy
                // kartograficzny trik na czytelność trasy na dowolnym tle,
                // zamiast polegać samym kolorem/dashem o kontrast. Nadal
                // dokładna geometria (`leg.route.path`) i styl per tryb
                // transportu (`RouteProvider.lineWidth`/`lineDashPattern`,
                // ta sama konwencja co flythrough).
                // Linia ZWĘŻONA (18.08.2026, user: "te linie są za grube, to
                // wygląda strasznie") — halo ledwo szersze od głównej linii
                // (+1.5 zamiast +4), sama linia cieńsza (bazowe `lineWidth`
                // BEZ dodatku, tylko dash pattern robi różnicę per tryb) —
                // subtelna obwódka dla czytelności, nie gruba, dominująca
                // kreska. KOLOR PER TRYB TRANSPORTU (`RouteProvider.color`,
                // 18.08.2026) zamiast jednolitego niebieskiego — user po
                // zobaczeniu referencji: "każdy środek transportu powinien
                // mieć własny kolor".
                ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                    let mode = TransportMode(rawValue: leg.to.transportRawValue) ?? .plane
                    MapPolyline(coordinates: leg.route.path)
                        .stroke(
                            .white.opacity(0.8),
                            style: StrokeStyle(lineWidth: RouteProvider.lineWidth(for: mode) + 1.5, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: leg.route.path)
                        .stroke(
                            RouteProvider.color(for: mode),
                            style: StrokeStyle(
                                lineWidth: RouteProvider.lineWidth(for: mode),
                                lineCap: .round,
                                lineJoin: .round,
                                dash: RouteProvider.lineDashPattern(for: mode).map { CGFloat($0) }
                            )
                        )
                }
                // Ikona pojazdu w połowie każdego odcinka — patrz
                // `vehicleIcons` wyżej.
                ForEach(vehicleIcons, id: \.id) { icon in
                    Annotation("", coordinate: icon.coordinate) {
                        Image(icon.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(icon.rotationDegrees))
                            .shadow(radius: 2)
                    }
                }
            }
            .mapStyle(MapTheme.satellite.mapStyle)
            .onAppear {
                // Ten sam wzorzec co `WorldGlobeView` (01.08.2026) — start
                // WPROST na region dopasowany do przystanków, żeby markery
                // nie "zniknęły" przy zbyt dalekim domyślnym zoomie.
                guard !hasSetInitialCamera else { return }
                hasSetInitialCamera = true
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(Self.region(for: sortedStops.map(\.coordinate)))
                }
            }

            if isLoadingLegs {
                ProgressView()
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 40)
            }

            if let selectedLeg {
                LegInfoCard(from: selectedLeg.from, to: selectedLeg.to, route: selectedLeg.route)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Zawartość wysuwanego panelu "Itinerary" (18.08.2026) — lista
    /// odcinków, numerek w KOLORZE TRYBU danego odcinka (spójny z linią na
    /// mapie), tapnięcie przybliża kamerę do TEGO odcinka.
    ///
    /// PRZEBUDOWANE (18.08.2026, ciąg dalszy) — user: "lista na dole jest
    /// słaba, nie da się jej przewijać, tylko wyskakuje cała na ekran i
    /// odstępy są na niej za duże". `Section`+nagłówek `List` dokładał
    /// sporo domyślnego odstępu, a `VStack` z emoji+etykietą trybu po
    /// prawej rozdymał wysokość wiersza bez potrzeby (ta sama informacja
    /// już jest w numerku+kolorze). Zamiast tego: WŁASNY tytuł nad listą
    /// (bez wbudowanego nagłówka Sekcji), `.listRowInsets`/`.listRowSeparator`
    /// dociśnięte, jedna zwarta linia per wiersz (emoji WEWNĄTRZ tekstu
    /// zamiast osobnej kolumny) — więcej wierszy mieści się w tej samej
    /// wysokości, realnie przewijalne.
    private var itineraryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Itinerary"))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            List {
                ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                    Button {
                        zoomToLeg(leg)
                    } label: {
                        itineraryRow(index: index, leg: leg)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }

    private func itineraryRow(index: Int, leg: Leg) -> some View {
        let mode = TransportMode(rawValue: leg.to.transportRawValue) ?? .plane
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RouteProvider.color(for: mode), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("\(mode.emoji) \(leg.from.cityName) → \(leg.to.cityName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(itinerarySubtitle(for: leg))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func itinerarySubtitle(for leg: Leg) -> String {
        let duration = Self.legDurationText(leg.route.durationMinutes)
        guard let date = leg.to.arrivalDate else { return duration }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) · \(duration)"
    }

    /// Tapnięcie wiersza w Itinerary (18.08.2026) — przybliża kamerę do
    /// DWÓCH punktów tego odcinka, reużywa `region(for:minimumDelta:)`
    /// wyżej z ciaśniejszym marginesem niż start ekranu (mniejszy obszar
    /// do pokazania).
    private func zoomToLeg(_ leg: Leg) {
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(Self.region(for: [leg.from.coordinate, leg.to.coordinate], minimumDelta: 1))
        }
    }

    /// Buduje trasę KAŻDEGO odcinka na żywo (nie persystowaną — świadomie,
    /// żeby uniknąć nowego pola/migracji SwiftData, patrz plan). Współrzędne
    /// i tryb transportu wyciągnięte do zwykłych wartości PRZED
    /// rozgałęzieniem na równoległe zadania — `SavedStop` to referencyjny
    /// model SwiftData związany z `ModelContext`, ten sam ostrożny wzorzec
    /// co `TravelMapView.persistTrip` (tam sekwencyjnie z tego samego
    /// powodu): nie przekazujemy obiektów `@Model` MIĘDZY zadaniami,
    /// `SavedStop` dotykany tylko na aktorze widoku, przed i po.
    private func loadLegs() async {
        let stops = sortedStops
        guard stops.count >= 2 else {
            isLoadingLegs = false
            return
        }
        let legInputs: [(index: Int, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transport: TransportMode)] =
            (1..<stops.count).map { index in
                let transport = TransportMode(rawValue: stops[index].transportRawValue) ?? .plane
                return (index, stops[index - 1].coordinate, stops[index].coordinate, transport)
            }
        let routes: [Int: RouteResult] = await withTaskGroup(of: (Int, RouteResult).self) { group in
            for input in legInputs {
                group.addTask {
                    let route = await RouteProvider.route(from: input.from, to: input.to, transport: input.transport)
                    return (input.index, route)
                }
            }
            var collected: [Int: RouteResult] = [:]
            for await (index, route) in group {
                collected[index] = route
            }
            return collected
        }
        legs = (1..<stops.count).compactMap { index in
            guard let route = routes[index] else { return nil }
            return Leg(from: stops[index - 1], to: stops[index], route: route)
        }
        isLoadingLegs = false
    }

    /// Ten sam wzorzec co `WorldGlobeView.initialRegion(for:)` — region
    /// dopasowany do PODANYCH współrzędnych, minimalna rozpiętość (żeby
    /// jeden/bliskie sobie punkty nie dały zerowego przybliżenia), margines
    /// 60%. Generyczne (nie tylko "wszystkie przystanki", 18.08.2026) —
    /// reużywane też przez `zoomToLeg` z DWOMA punktami i ciaśniejszym
    /// `minimumDelta`.
    private static func region(for coordinates: [CLLocationCoordinate2D], minimumDelta: Double = 4) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            )
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.6, minimumDelta)
        let lonDelta = max((maxLon - minLon) * 1.6, minimumDelta)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    /// Czas TEGO odcinka, "2h 31min" styl — reużywany przez `LegInfoCard`
    /// (karta po tapnięciu markera) i wiersze Itinerary.
    fileprivate static func legDurationText(_ minutes: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: minutes * 60) ?? ""
    }

    /// Suma czasu CAŁEJ podróży, "13d 14h" styl (18.08.2026, pasek
    /// statystyk) — dni+godziny zamiast godziny+minuty, bo suma wielu
    /// odcinków łatwo przekracza dobę.
    private static func totalDurationText(_ minutes: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: minutes * 60) ?? ""
    }
}

/// Marker per przystanek — duża miniaturka zdjęcia w kółku z białym
/// obramowaniem (fallback: flaga kraju), styl zbliżony do zrzutu Polarsteps
/// który user pokazał (18.08.2026) — powiększone z 36pt do 60pt, numer
/// kroku CELOWO USUNIĘTY (nie ma go na referencyjnym zrzucie; "coś w
/// naszym stylu", nie kopiować 1:1, ale to konkretnie zbędne). Pulsująca
/// obwódka "tu jesteś teraz" ze zrzutu ŚWIADOMIE POMINIĘTA — to wskaźnik
/// NA ŻYWO z prawdziwego trackera, PMemories nie śledzi GPS na żywo, ta
/// podróż jest już zakończona/zapisana.
private struct RouteStopMarker: View {
    let stop: SavedStop
    /// Etykieta NAD zdjęciem zamiast POD (18.08.2026) — naprzemienne wg
    /// indeksu przystanku, patrz komentarz przy wywołaniu w `body`. Pusty
    /// `VStack` odwraca kolejność zamiast osobnego layoutu.
    let labelAbove: Bool
    /// "START"/"FINISH" dla pierwszego/ostatniego przystanku, `nil` dla
    /// środkowych (18.08.2026, z mockupu usera).
    let badge: String?
    @State private var thumbnail: UIImage?

    private var photoCircle: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            } else {
                Text(CityGeocoder.flagEmoji(countryCode: stop.countryCode))
                    .font(.system(size: 30))
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            }
        }
        .shadow(radius: 4)
    }

    /// Data pobytu — jedna wartość, KRÓTKO sformatowana (18.08.2026, z
    /// mockupu). Uczciwe ograniczenie: `SavedStop` ma tylko `arrivalDate`,
    /// nie parę check-in/check-out jak `PlannedStop` — appka nie zna
    /// ZAKRESU dat dla ODBYTYCH podróży, tylko pojedynczy dzień.
    private var dateText: String? {
        guard let date = stop.arrivalDate else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // Etykieta z nazwą miasta (18.08.2026, user po zobaczeniu mockupu z
    // podpisanymi znacznikami) — flaga + nazwa + opcjonalnie START/FINISH i
    // data, na ciemnej "pigułce", czytelne na dowolnym tle mapy.
    private var cityLabel: some View {
        VStack(spacing: 1) {
            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("\(CityGeocoder.flagEmoji(countryCode: stop.countryCode)) \(stop.cityName)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let dateText {
                Text(dateText)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(radius: 2)
    }

    var body: some View {
        VStack(spacing: 4) {
            if labelAbove {
                cityLabel
                photoCircle
            } else {
                photoCircle
                cityLabel
            }
        }
        .task(id: stop.representativePhotoIdentifier) {
            guard let identifier = stop.representativePhotoIdentifier else { return }
            thumbnail = await MediaAssetLoader.markerThumbnail(forAssetLocalIdentifier: identifier)
        }
    }
}

/// Karta pokazana po tapnięciu przystanku — tryb transportu, miasta,
/// dystans (`.formatted()`, ten sam wzorzec separatora tysięcy co reszta
/// appki od 13.08.2026) i szacowany czas przejazdu (`DateComponentsFormatter`,
/// "2h 31min" styl).
private struct LegInfoCard: View {
    let from: SavedStop
    let to: SavedStop
    let route: RouteResult

    private var mode: TransportMode {
        TransportMode(rawValue: to.transportRawValue) ?? .plane
    }

    private var durationText: String {
        TravelRouteOverviewView.legDurationText(route.durationMinutes)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(mode.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Palette.blue.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(from.cityName) → \(to.cityName)")
                    .font(.subheadline.weight(.semibold))
                Text("\(Int(route.distanceKm.rounded()).formatted()) km · \(durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 6)
    }
}
