import MapKit
import CoreLocation
import SwiftUI

/// Ścieżka do narysowania (może być stylizowana, np. łuk lotu) razem z
/// PRAWDZIWYM dystansem odcinka — to dwie osobne rzeczy: łuk jest tylko
/// wizualny (dłuższy niż faktyczna odległość), więc licznik km musi liczyć
/// z `distanceKm`, nigdy z długości `path`.
///
/// `durationMinutes` (18.08.2026, statyczny przegląd trasy z tapnięciem =
/// dystans/czas) — REALNY czas z `MKDirections`'s `expectedTravelTime` dla
/// odcinków z prawdziwym trasowaniem (samochód/pociąg/piesza trasa),
/// ESTYMOWANY z założonej prędkości przelotowej (`RouteProvider.
/// estimatedSpeedKmh`) gdy żadne API nie daje realnego czasu (samolot/
/// prom/statek wycieczkowy, nazwany szlak z Overpass, ostateczny fallback
/// geodezyjny) — jasno oznaczone w miejscach użycia jako przybliżenie, nie
/// fakt z API.
struct RouteResult {
    let path: [CLLocationCoordinate2D]
    let distanceKm: Double
    let durationMinutes: Double
}

/// Dostarcza ścieżkę do narysowania między dwoma przystankami, zależnie od
/// środka transportu: prawdziwa trasa drogowa/kolejowa gdy się da, w
/// przeciwnym razie łuk geodezyjny (najkrótsza droga po kuli ziemskiej).
enum RouteProvider {
    static func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transport: TransportMode) async -> RouteResult {
        switch transport {
        case .car:
            if let real = await directionsRoute(from: from, to: to, transportType: .automobile) {
                return real
            }
        case .train:
            if let real = await directionsRoute(from: from, to: to, transportType: .transit) {
                return real
            }
            // Pokrycie tras transit jest bardzo nierówne poza dużymi miastami/krajami
            // (np. Londyn→Paryż przez kanał La Manche — transit MKDirections nie ma
            // trasy w ogóle). Zanim spadniemy do gołej linii prostej (mogłaby
            // przelecieć nad wodą — pociąg fizycznie tego nie robi), spróbujmy
            // GEOMETRII trasy drogowej: pociąg i tak jeździ mniej więcej po lądzie
            // tak jak drogi, więc ŚCIEŻKA to bardziej realistyczne przybliżenie niż
            // czysta geodezja.
            //
            // CZAS PRZEJAZDU (18.08.2026, naprawiony realny bug — user zgłosił
            // Londyn→Paryż pokazujące 6h) — NIE dziedziczony wprost z auta. Trasa
            // samochodowa przez Eurotunnel ma realny czas ~6h (postój na
            // przeprawę), ale to czas SAMOCHODU, nie pociągu (Eurostar ~2h15).
            // Estymowany z `estimatedSpeedKmh(for: .train)` na DYSTANSIE trasy
            // drogowej — nadal tylko PRZYBLIŻENIE (appka nie ma dostępu do
            // realnych rozkładów kolejowych, świadomie poza zakresem, ten sam
            // powód co brak płatnego API tras pieszych przy wędrówce wyżej), ale
            // bliższe prawdy niż czas auta.
            if let roadFallback = await directionsRoute(from: from, to: to, transportType: .automobile) {
                let estimatedMinutes = roadFallback.distanceKm / estimatedSpeedKmh(for: .train) * 60
                return RouteResult(path: roadFallback.path, distanceKm: roadFallback.distanceKm, durationMinutes: estimatedMinutes)
            }
        case .hiking:
            // Najpierw prawdziwy, NAZWANY szlak (OpenStreetMap `route=hiking`,
            // ta sama baza co Waymarked Trails) jeśli jego geometria
            // przechodzi blisko obu końców odcinka — dużo bardziej autentyczne
            // niż zwykła trasa piesza po drogach. Overpass to baza danych, nie
            // silnik routingu — działa tylko gdy realny szlak faktycznie
            // istnieje w okolicy obu punktów (patrz `WaymarkedTrailProvider`),
            // więc w praktyce to "użyj prawdziwego szlaku gdy jest", nie pełne
            // trasowanie po dowolnych dwóch punktach (to wymagałoby płatnego/
            // kluczowanego serwisu, świadomie poza zakresem — `Docs/Travel.md`).
            if let trail = await WaymarkedTrailProvider.route(from: from, to: to) {
                return trail
            }
            // Realna trasa piesza (ścieżki/szlaki w danych Apple Maps) —
            // zero GPS-a usera, appka tylko pyta o trasę między dwoma
            // punktami, tak samo jak dla samochodu/pociągu. Fallback gdy
            // żaden nazwany szlak nie pasuje.
            if let real = await directionsRoute(from: from, to: to, transportType: .walking) {
                return real
            }
        case .plane, .boat, .cruise:
            break
        }

        let straightLineKm = straightDistanceKm(from: from, to: to)
        let estimatedMinutes = straightLineKm / estimatedSpeedKmh(for: transport) * 60
        switch transport {
        case .plane:
            return RouteResult(path: arcedGeodesic(from: from, to: to), distanceKm: straightLineKm, durationMinutes: estimatedMinutes)
        case .boat:
            return RouteResult(path: wavyGeodesic(from: from, to: to), distanceKm: straightLineKm, durationMinutes: estimatedMinutes)
        default:
            return RouteResult(path: geodesicCoordinates(from: from, to: to), distanceKm: straightLineKm, durationMinutes: estimatedMinutes)
        }
    }

    /// Założona prędkość przelotowa PRZYBLIŻONA (18.08.2026) — używana
    /// WYŁĄCZNIE gdy żadne API nie daje realnego czasu przejazdu (patrz
    /// `RouteResult.durationMinutes`). Samolot uwzględnia start/lądowanie/
    /// kołowanie (niżej niż czysta prędkość przelotowa ~900 km/h), reszta
    /// to zgrubne, rozsądne średnie — user widzi te liczby jako szacunek w
    /// karcie odcinka trasy, nie jako gwarantowany czas lotu/przejazdu.
    static func estimatedSpeedKmh(for transport: TransportMode) -> Double {
        switch transport {
        case .plane: return 700
        case .boat: return 35
        case .cruise: return 30
        case .car: return 60
        // 18.08.2026: 80→100 — bliżej realnej średniej połączeń
        // międzymiastowych/ekspresowych w Europie (uwzględniając postoje),
        // nadal ZGRUBNE przybliżenie — appka nie zna prawdziwych
        // rozkładów, nie odróżni regionalnego pociągu od Eurostar/TGV.
        case .train: return 100
        case .hiking: return 4
        }
    }

    /// Styl linii trasy na mapie zależny od środka transportu — samolot
    /// przerywana (jak na flight-trackerach), pociąg gęściej przerywana
    /// (sugeruje szyny/podkłady bez rysowania prawdziwych poprzeczek),
    /// samochód ciągła, prom ciągła (falowanie ma już samo w sobie w
    /// kształcie ścieżki — `wavyGeodesic`), statek wycieczkowy grubsza.
    static func lineWidth(for transport: TransportMode) -> Double {
        transport == .cruise ? 4 : 2
    }

    static func lineDashPattern(for transport: TransportMode) -> [Double] {
        switch transport {
        case .plane: return [10, 8]
        case .train: return [3, 5]
        // Kropkowana — konwencja z map turystycznych dla szlaków pieszych.
        case .hiking: return [1, 4]
        default: return []
        }
    }

    /// Kolor linii per środek transportu (18.08.2026, `TravelRouteOverviewView`
    /// — user po zobaczeniu referencji: "każdy środek transportu powinien
    /// mieć własny kolor"). User potwierdził że kolor ma zostać PRZY TRYBIE
    /// (nie per konkretny odcinek — "nie będziemy oglądać innych tras
    /// jednocześnie"), więc ta funkcja/architektura się nie zmienia.
    ///
    /// Wartości DOBRANE PONOWNIE (18.08.2026, ciąg dalszy) — user na
    /// realnym urządzeniu: samochód (pierwotnie `Palette.accent`,
    /// pomarańcz) zlewał się z natywnym żółto-pomarańczowym kolorem
    /// autostrad na satelitarnej mapie Apple, pociąg (pierwotnie
    /// `Palette.purple`) "praktycznie nie widać" na terenie górskim.
    ///
    /// TRZECIA runda (18.08.2026, jeszcze ciąg dalszy) — surowe systemowe
    /// `.red`/`.pink`/`.orange`/`.yellow`/`.brown` user ocenił jako
    /// "tragiczne", zbyt nasycone na tle satelitarnej mapy (referencja
    /// usera miała STONOWANE, miękkie tony). Zastąpione ręcznie dobranymi
    /// kolorami z `Palette.swift` (`coral`/`rose`/`gold`/`tan`, ten sam
    /// wzorzec co `blue`/`indigo`/`purple`/`accent` — `rgb()`, nie surowe
    /// systemowe kolory), zachowując tę samą logikę kontrastu względem tła
    /// (droga/teren/ocean) co poprzednia runda, tylko w miękkiej wersji.
    static func color(for transport: TransportMode) -> Color {
        switch transport {
        case .plane: return Palette.blue
        case .train: return Palette.teal
        case .car: return Palette.coral
        case .boat: return Palette.accent
        case .cruise: return Palette.gold
        case .hiking: return Palette.tan
        }
    }

    /// Realny bug 18.08.2026 (user: "dlaczego jest linia prosta pociągiem z
    /// Bellagio do Zurich?") — `try?` po cichu połykał błąd `MKDirections`,
    /// zero śladu DLACZEGO zapytanie zawiodło (transient sieciowy błąd?
    /// Bellagio geokodowane na jezioro, bez dostępu do drogi? Apple po
    /// prostu nie ma trasy?). Gdy WSZYSTKIE próby (transit + fallback
    /// samochodowy) zawiodą, appka spada na gołą linię geodezyjną — poprawne
    /// jako ostateczność, ale bez logu nie da się odróżnić "przejściowy
    /// błąd sieci" od "ten konkretny odcinek zawsze tak wygląda". Naprawa:
    /// JEDNO ponowienie (ten sam wzorzec co `PMemoriesOutroCardRenderer`,
    /// 15.08.2026) + jawny `print` przy każdej porażce, żeby przyszła
    /// diagnoza miała dowód zamiast zgadywania.
    private static func directionsRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async -> RouteResult? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = transportType

        var lastError: Error?
        for attempt in 1...2 {
            let directions = MKDirections(request: request)
            do {
                let response = try await AsyncTimeout.run(seconds: 10) {
                    try await directions.calculate()
                }
                if let route = response.routes.first {
                    let polyline = route.polyline
                    var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
                    polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
                    // route.distance to PRAWDZIWY dystans drogi/szyn w metrach —
                    // dokładniejszy i tańszy niż sumowanie odległości między
                    // punktami polylinii ręcznie. route.expectedTravelTime
                    // (18.08.2026) — REALNY czas z TEJ SAMEJ odpowiedzi
                    // `MKDirections`, wcześniej odrzucany bez użycia.
                    return RouteResult(path: coordinates, distanceKm: route.distance / 1000, durationMinutes: route.expectedTravelTime / 60)
                }
                print("⚠️ RouteProvider: \(transportType.rawValue) \(from)→\(to) — brak tras w odpowiedzi (próba \(attempt)/2)")
            } catch {
                lastError = error
                print("⚠️ RouteProvider: \(transportType.rawValue) \(from)→\(to) — błąd \(error) (próba \(attempt)/2)")
            }
        }
        print("⚠️ RouteProvider: \(transportType.rawValue) \(from)→\(to) — zawiodło po 2 próbach (\(lastError?.localizedDescription ?? "brak tras")), spadam na fallback")
        return nil
    }

    /// Wygładza realną trasę (z `MKDirections`) uśrednieniem ruchomym —
    /// prawdziwe drogi/tory mają mnóstwo drobnych, ulicznych zakrętów,
    /// niewidocznych przy starym, dalekim zoomie kamery, ale przy nowym,
    /// bliskim zoomie (`TravelCinematics`, adaptacyjny dystans) każdy z nich
    /// stawał się widocznym, ostrym szarpnięciem kamery — user: "auto/pociąg
    /// strasznie się trzęsie". Kamera i rysowana linia trasy używają TEJ
    /// SAMEJ wygładzonej ścieżki (dystans w km liczony ZAWSZE osobno, z
    /// `route.distance`/`straightDistanceKm` — to wygładzenie nigdy go nie
    /// dotyka). Łuki lotu/fal promu (`arcedGeodesic`/`wavyGeodesic`) już są
    /// z natury gładkie (matematyczne krzywe) — nie potrzebują tego kroku.
    static func smoothedPath(_ path: [CLLocationCoordinate2D], windowRadius: Int = 3) -> [CLLocationCoordinate2D] {
        guard path.count > windowRadius * 2 else { return path }
        var result = path.indices.map { index -> CLLocationCoordinate2D in
            let lo = max(0, index - windowRadius)
            let hi = min(path.count - 1, index + windowRadius)
            let window = path[lo...hi]
            let avgLat = window.map(\.latitude).reduce(0, +) / Double(window.count)
            let avgLon = window.map(\.longitude).reduce(0, +) / Double(window.count)
            return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
        }
        // BUG znaleziony 01.08.2026 (user: "lotnisko pokazuje nie w
        // miejscu gdzie ląduje samolot", to samo z pociągiem/każdym
        // środkiem transportu) — uśrednianie ruchome PRZESUWAŁO też
        // PIERWSZY i OSTATNI punkt ścieżki (okno wciąż bierze kilka
        // sąsiednich punktów nawet na samym skraju), więc narysowana linia
        // trasy nie zaczynała/kończyła się DOKŁADNIE na współrzędnej
        // przystanku — a to WŁAŚNIE ta współrzędna (nie wygładzona
        // ścieżka) jest używana do rysowania pinezki/chorągiewki
        // (`composite`/`showStopFlag`). Efekt: pinezka "nie trafiała" w
        // koniec linii, czasem o zauważalny kawałek przy realnych trasach
        // samochodowych/kolejowych (więcej "szumu" blisko końców niż przy
        // gładkim łuku lotu). Naprawa: wygładzamy WYŁĄCZNIE wnętrze
        // ścieżki, pierwszy/ostatni punkt zostają dokładnie takie jak w
        // źródłowej trasie.
        result[0] = path[0]
        result[result.count - 1] = path[path.count - 1]
        return result
    }

    /// Zmienia rozmiar ścieżki na dokładnie `targetCount` punktów, równo
    /// rozłożonych po UŁAMKU trasy (interpolacja liniowa) — niezależnie od
    /// tego, jak gęsta/rzadka była oryginalna trasa. Bez tego, gdy
    /// `path.count` (realne punkty z `MKDirections`) było mniejsze niż
    /// liczba kroków animacji, wiele kolejnych kroków trafiało w TEN SAM
    /// punkt (całkowitoliczbowe zaokrąglenie indeksu) — kamera "stała w
    /// miejscu, po czym skakała" zamiast płynnie jechać. To osobny problem
    /// od `smoothedPath` (tamto wygładza KSZTAŁT trasy, to naprawia GĘSTOŚĆ
    /// próbkowania) — user: "pociąg też się trzęsie" utrzymywało się nawet
    /// po samym wygładzeniu kształtu, dopóki nie dodano tego kroku.
    /// Wołane PRZED `smoothedPath` (upsampling najpierw, wygładzenie na
    /// gęstszych danych daje czystszy efekt).
    static func resamplePath(_ path: [CLLocationCoordinate2D], targetCount: Int) -> [CLLocationCoordinate2D] {
        guard path.count > 1, targetCount > 1 else { return path }
        return (0..<targetCount).map { i in
            let fraction = Double(i) / Double(targetCount - 1)
            let scaledIndex = fraction * Double(path.count - 1)
            let lowerIndex = Int(scaledIndex)
            let upperIndex = min(path.count - 1, lowerIndex + 1)
            let t = scaledIndex - Double(lowerIndex)
            let lower = path[lowerIndex]
            let upper = path[upperIndex]
            return CLLocationCoordinate2D(
                latitude: lower.latitude + (upper.latitude - lower.latitude) * t,
                longitude: lower.longitude + (upper.longitude - lower.longitude) * t
            )
        }
    }

    /// Wygodne złożenie `resamplePath` + `smoothedPath` w jednym wywołaniu —
    /// to zawsze idą razem (upsampling przed wygładzeniem), więc oba miejsca
    /// wołające (podgląd + eksport) mają jedno miejsce do utrzymania.
    static func cinematicPath(_ path: [CLLocationCoordinate2D], targetCount: Int = 200) -> [CLLocationCoordinate2D] {
        smoothedPath(resamplePath(path, targetCount: targetCount))
    }

    static func geodesicCoordinates(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let line = MKGeodesicPolyline(coordinates: [from, to], count: 2)
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: line.pointCount)
        line.getCoordinates(&coordinates, range: NSRange(location: 0, length: line.pointCount))
        return coordinates
    }

    /// Prawdziwa odległość "w linii prostej" (po powierzchni kuli ziemskiej)
    /// między dwoma punktami — to jest to, co pokazujemy w liczniku km dla
    /// lotów/promów, NIE długość stylizowanego łuku.
    static func straightDistanceKm(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let b = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return a.distance(from: b) / 1000
    }

    /// BUG znaleziony 01.08.2026 (user: "punkty startu i lądowania się
    /// przemieszczają, nie zostają na mapie") — potwierdzone piksel po
    /// pikselu na wysłanym filmiku: karta "LONDON STANSTED AIRPORT"
    /// wyjeżdżała poza krawędź ekranu w połowie długiego lotu (~2800 km z
    /// 3000 km), bo kamera lotu podążała za DOKŁADNĄ bieżącą pozycją
    /// samolotu — przy stałym, szerokim dystansie (`ceilingDistance`) start
    /// w końcu wypada poza widoczny kadr. Prosty środek geometryczny
    /// (nie geodezyjny) — wystarczająco dokładny do samego KADROWANIA
    /// kamery (nie do nawigacji), i dużo prostszy niż liczenie prawdziwego
    /// środka wielkiego koła.
    static func midpoint(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (from.latitude + to.latitude) / 2,
            longitude: (from.longitude + to.longitude) / 2
        )
    }

    /// BUG znaleziony 12.08.2026 (user: "samochód jak by znikał, na końcu
    /// jest tragiczna" — potwierdzone klatka po klatce: pojazd zamierał w
    /// miejscu tuż przed przyjazdem, mimo że licznik km dalej rósł płynnie)
    /// — pozycja pojazdu w `TravelMapVideoRenderer` liczyła się jako
    /// `path[Int(count * progress)]`, czyli ZAOKRĄGLONY w dół indeks na
    /// ścieżce o ograniczonej rozdzielczości (~200 punktów z
    /// `cinematicPath`). Krzywa `easeInOutCubic` spłaszcza się mocno przy
    /// końcu (zwolnienie przed przyjazdem) — wiele kolejnych, dyskretnych
    /// klatek trafiało wtedy w DOKŁADNIE TEN SAM zaokrąglony indeks, więc
    /// pojazd wizualnie stał w miejscu. Prosta liniowa interpolacja MIĘDZY
    /// dwoma sąsiednimi punktami ścieżki (nie geodezyjna — punkty i tak są
    /// blisko siebie na tym poziomie szczegółowości) daje płynną,
    /// ciągłą pozycję niezależnie od rozdzielczości `path`/krzywej
    /// prędkości.
    static func interpolate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }

    /// Geodezyjna trasa lotu z dodanym stylizowanym łukiem (jak w prawdziwych
    /// apkach flight-tracker) — WYŁĄCZNIE do rysowania. Łuk wydłuża linię
    /// względem faktycznej odległości, dlatego dystans do wyświetlenia liczymy
    /// zawsze osobno, z `straightDistanceKm`, nigdy z tej ścieżki.
    private static func arcedGeodesic(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let base = geodesicCoordinates(from: from, to: to)
        guard base.count > 2 else { return base }

        let start = base.first!
        let end = base.last!
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return base }

        // Wektor prostopadły do kierunku trasy (przybliżenie płaskie —
        // wystarczające dla samego efektu wizualnego łuku).
        let perpX = -dy / length
        let perpY = dx / length
        // BUG znaleziony 01.08.2026 (user: "dashed route starts in the
        // Atlantic Ocean instead of starting exactly at London Stansted
        // Airport" — trafna, precyzyjna diagnoza) — `length` to surowe
        // stopnie szer./dł. geogr. (NIE km), więc dla długiego lotu
        // (Londyn→Teneryfa, ~29° ≈ 3000 km) stary wzór (`length*0.15`,
        // limit 8.0°) dawał `bowHeight` ≈4.35° ≈ 480 km wygięcia w
        // najszerszym miejscu — matematycznie PIERWSZY punkt trasy nadal
        // był dokładnie na lotnisku (sin(0)=0), ale krzywa odchylała się
        // dramatycznie w bok (w stronę Atlantyku) już po kilku procentach
        // trasy, wizualnie wyglądając jakby "nie zaczynała się" na
        // lotnisku. Zmniejszony współczynnik (0.15→0.06) i twardy limit
        // (8.0°→2.5° ≈ 280 km) — wciąż wyraźny, stylizowany łuk jak w
        // prawdziwych apkach flight-tracker, ale bez rysowania nad
        // otwartym oceanem daleko od faktycznej trasy.
        let bowHeight = min(length * 0.06, 2.5)

        return base.enumerated().map { index, coordinate in
            let t = Double(index) / Double(base.count - 1)
            let bow = sin(t * .pi) * bowHeight
            return CLLocationCoordinate2D(
                latitude: coordinate.latitude + perpY * bow,
                longitude: coordinate.longitude + perpX * bow
            )
        }
    }

    /// Geodezyjna trasa promu z delikatnym falowaniem — WYŁĄCZNIE do
    /// rysowania (jak `arcedGeodesic`, ale wiele małych oscylacji zamiast
    /// jednego łuku, żeby wyglądało jak fale, nie jak wygięcie trasy).
    /// Dystans do wyświetlenia liczony osobno, z `straightDistanceKm`.
    private static func wavyGeodesic(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let base = geodesicCoordinates(from: from, to: to)
        guard base.count > 2 else { return base }

        let start = base.first!
        let end = base.last!
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return base }

        let perpX = -dy / length
        let perpY = dx / length
        // Mała amplituda (dużo mniejsza niż łuk lotu) i kilka pełnych fal na
        // całej trasie, wygaszana do zera na obu końcach (sin(t*π)), żeby
        // fala nie była widoczna dokładnie w portach wejścia/wyjścia.
        let waveHeight = min(length * 0.02, 1.2)
        let waveCount = 6.0

        return base.enumerated().map { index, coordinate in
            let t = Double(index) / Double(base.count - 1)
            let envelope = sin(t * .pi)
            let wave = sin(t * waveCount * .pi) * waveHeight * envelope
            return CLLocationCoordinate2D(
                latitude: coordinate.latitude + perpY * wave,
                longitude: coordinate.longitude + perpX * wave
            )
        }
    }

    /// Namiar (w stopniach) z punktu `from` do `to` — współdzielone między
    /// żywym podglądem i eksportem (były to dwie osobne, identyczne kopie
    /// tego samego wzoru w `TravelMapAnimationView.bearing`/
    /// `TravelMapVideoRenderer.geographicBearing` — scalone tu 29.07.2026
    /// przy okazji Travel Cinematic Engine, żeby nie mogły się rozjechać).
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}
