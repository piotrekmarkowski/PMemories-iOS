import Foundation

/// "Travel Cinematic Engine" — matematyka kamery/ikony współdzielona między
/// żywym podglądem (`TravelMapAnimationView`, SwiftUI) i eksportem wideo
/// (`TravelMapVideoRenderer`, raw `MKMapView`/CGContext). Celowo BEZ importu
/// CoreLocation/MapKit/SwiftUI/UIKit — same liczby (metry, stopnie), żeby oba
/// miejsca wołały dokładnie tę samą funkcję i nie mogły się rozjechać
/// wizualnie (ustalony wcześniej, twardy wymóg: 100% zgodność podglądu z
/// eksportem).
///
/// Zastępuje stały `globeDistance = 12_000_000` (ten sam dla KAŻDEGO odcinka,
/// niezależnie od długości) — user: nakładające się etykiety miast przy
/// długich trasach (potwierdzone screenshotem, 2244 km Londyn→Włochy) i
/// "niewidoczny" ruch przy krótkich odcinkach (potwierdzone klatkami z
/// wyeksportowanego wideo — zero widocznego przesunięcia kamery na trasie
/// samochód+pociąg). Kamera pozostaje ZAWSZE north-up (`heading: 0`) —
/// świadomie NIE przywracamy obracającej się kamery pościgowej, odrzuconej
/// wcześniej (27.07.2026, "kamera nie nadąża za samolotem").
enum TravelCinematics {
    struct FrameState {
        let cameraDistance: Double
        let cameraPitch: Double
        let iconScale: Double
    }

    /// Najbliżej jak kamera może podejść — nadal widok satelitarny/z lotu
    /// ptaka, nie nawigacja uliczna jak w zwykłych Mapach.
    static let floorDistance: Double = 35_000
    /// = dawny stały `globeDistance` — długie trasy (loty międzykontynentalne)
    /// wyglądają DOKŁADNIE tak samo jak dotąd, zero regresji.
    static let ceilingDistance: Double = 12_000_000

    /// Bug znaleziony 04.08.2026 (user, trasa Grenlandia/Kanada→Afryka
    /// Zach., kilka tys. km) — stały, szeroki kadr lotu (patrz `frameState`
    /// niżej) trzyma OBA lotniska w kadrze przez cały odcinek, co dla
    /// KRÓTKICH/ŚREDNICH lotów wygląda dobrze (etykiety czytelne, samolot
    /// wyraźnie widoczny — user: "zostawiamy jak jest"), ale przy bardzo
    /// długich dystansach kamera musi być tak szeroka, że samolot ginie w
    /// ogromnym, niezmiennym kadrze oceanu, a karta lotniska bywa ucięta na
    /// krawędzi ekranu. Próg: powyżej tego dystansu lot używa TEJ SAMEJ
    /// kamery "podążającej" co reszta środków transportu (`baseCameraDistance`
    /// i tak ucina się na tej samej szerokiej wartości dla dystansów ≥6000km,
    /// więc faza przelotowa wygląda podobnie szeroko jak dziś — różni się
    /// TYLKO to że kamera podąża za samolotem zamiast trzymać stały środek).
    /// Wartość startowa do dostrojenia z userem na realnych trasach — nie
    /// ostateczna, świadomie zaokrąglona do górnej kotwicy `distanceAnchors`.
    static let longFlightFollowThresholdKm: Double = 4_000

    /// Kotwice interpolacji w przestrzeni `log10(km)` — płynne w wielu
    /// rzędach wielkości, i to zwykła, łatwa do przestrojenia tabela zamiast
    /// nieczytelnego wzoru dobranego pod 5 przykładów naraz.
    /// Przestrojone 30.07.2026 (bliższe wartości dla odcinków 1-500 km) —
    /// user po pierwszym teście: "trochę lepiej, ale możemy jeszcze
    /// ulepszyć przy bliskich trasach, po prostu większe zbliżenie".
    /// PRZESTROJONE PONOWNIE 31.07.2026 — po naprawieniu proporcji ikon
    /// pojazdów (patrz `VehicleIconSet`/`TravelMapVideoRenderer.composite`)
    /// user zauważył, że pojazd jest "mikroskopijnej wielkości", kamera
    /// "jak satelita, nie dron". Zakres 10-3000 km (większość realnych tras)
    /// ściągnięty wyraźnie bliżej (mniej więcej dwukrotnie mniejszy dystans
    /// = dwukrotny zoom) — np. odcinek ~970 km miał kamerę na ~4.8 mln m,
    /// teraz ma ~2.2 mln m. Kotwica 6000 km (loty międzykontynentalne) BEZ
    /// ZMIAN — świadomie chroniony "płaski widok globusu" dla bardzo
    /// długich tras, zaakceptowany wcześniej, nie przedmiot tej uwagi.
    private static let distanceAnchors: [(km: Double, meters: Double)] = [
        (1, 35_000),
        (10, 65_000),
        (50, 180_000),
        (150, 450_000),
        (500, 1_100_000),
        (1_500, 3_000_000),
        (3_000, 7_000_000),
        (6_000, 12_000_000)
    ]

    /// Bazowy (fazy "cruise", mnożnik 1.0) dystans kamery dla danej długości
    /// odcinka — interpolacja liniowa między sąsiednimi kotwicami w skali
    /// logarytmicznej.
    static func baseCameraDistance(legDistanceKm: Double) -> Double {
        let km = max(distanceAnchors.first!.km, min(legDistanceKm, distanceAnchors.last!.km))
        for i in 1..<distanceAnchors.count {
            let lo = distanceAnchors[i - 1]
            let hi = distanceAnchors[i]
            if km <= hi.km {
                let t = (log10(km) - log10(lo.km)) / (log10(hi.km) - log10(lo.km))
                return lo.meters + (hi.meters - lo.meters) * t
            }
        }
        return distanceAnchors.last!.meters
    }

    /// Standardowa krzywa eased (szybciej w środku, wolniej na krawędziach)
    /// zamiast czysto liniowego `progress` — appka wcześniej nie miała żadnej
    /// funkcji easingu, cały ruch był liniowy krok-po-kroku.
    static func easeInOutCubic(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }

    private static func growPhaseT(_ progress: Double, growPhase: Double) -> Double {
        guard progress < growPhase else { return 1 }
        return easeInOutCubic(progress / growPhase)
    }

    private static func shrinkPhaseT(_ progress: Double, shrinkStart: Double) -> Double {
        guard progress > shrinkStart else { return 0 }
        return easeInOutCubic((progress - shrinkStart) / (1 - shrinkStart))
    }

    /// 01.08.2026 — user: "samolot jak startuje nie pomniejszamy ikon tylko
    /// bierzemy taka sama od startu i przy lądowaniu" — usunięta rampa
    /// zmniejszająca ikonę na starcie (0.25×) i przy lądowaniu (0.15×).
    /// Pojazd ma STAŁY rozmiar przez CAŁY odcinek, niezależnie od progresu.
    static func iconScale(progress: Double, growPhase: Double = 0.3, shrinkStart: Double = 0.75) -> Double {
        1.0
    }

    /// Bliski, "dronowy" dystans kamery na starcie/końcu KAŻDEGO odcinka —
    /// NIEZALEŻNY od długości trasy. PRZEPROJEKTOWANE 31.07.2026 (user,
    /// mocno: "gdzie to zbliżenie?? na końcu i na początku powinno być
    /// zbliżenie skąd i dokąd się przemieszczasz, nie zdjęcie satelitarne").
    /// Poprzednia wersja ("anticipation"/"landing") była PROCENTOWĄ redukcją
    /// dystansu przelotowego (`baseCameraDistance`) — dla długich odcinków
    /// nawet 0.8× czegoś dużego dalej wychodziło szeroko, satelitarnie, nie
    /// jak realny bliski kadr odlotu/przylotu.
    static let establishingDistance: Double = 100_000

    /// Obwiednia 0→1→0: `0` na `progress == 0/1` (pełne zbliżenie), `1` w
    /// fazie przelotowej (środek odcinka, pełny dystans `baseCameraDistance`).
    /// Iloczyn dwóch już istniejących, jednostronnych ramp — przy
    /// `growPhaseT` (rośnie 0→1, potem stałe 1) i `shrinkPhaseT` (stałe 0,
    /// potem rośnie 0→1) mnożenie automatycznie daje "0…1…0" bez osobnej,
    /// nowej krzywej do przetestowania.
    ///
    /// 01.08.2026 — chwilowo usunięta, potem PRZYWRÓCONA (user: "to
    /// wcześniejsze było lepsze, wracamy do oddalenia") — próba zostawienia
    /// stałego, bliskiego zbliżenia przez cały odcinek (bez pokazywania obu
    /// miast w połowie lotu) okazała się gorsza niż oryginał.
    private static func distanceEnvelope(progress: Double, growPhase: Double, shrinkStart: Double) -> Double {
        growPhaseT(progress, growPhase: growPhase) * (1 - shrinkPhaseT(progress, shrinkStart: shrinkStart))
    }

    /// Pochylenie kamery (0° = płasko z góry, jak dziś) zależne WYŁĄCZNIE od
    /// aktualnego, efektywnego dystansu — nie osobna krzywa. Dzięki temu
    /// "anticipation"/"landing" (które zmieniają dystans) automatycznie
    /// spłaszczają/pogłębiają pochylenie razem z zoomem, bez ryzyka że dwie
    /// niezależne krzywe się rozjadą. Przy `ceilingDistance` (długie trasy)
    /// `t` wychodzi DOKŁADNIE 0 — płaski widok "globusu" jest matematycznie
    /// niezmieniony, nie tylko w przybliżeniu.
    static func cameraPitch(forDistance distance: Double, maxPitch: Double = 55) -> Double {
        let clamped = max(floorDistance, min(ceilingDistance, distance))
        let t = (log10(ceilingDistance) - log10(clamped)) / (log10(ceilingDistance) - log10(floorDistance))
        return maxPitch * easeInOutCubic(t)
    }

    /// Docelowe czasy (sekundy, przy referencyjnej prędkości 1x/30fps) trzech
    /// faz KAŻDEGO odcinka lotu — user 01.08.2026, po rozpisaniu faz na
    /// czasy: "za długi postój skracamy do 1,5s, lądowanie wydłużamy do
    /// 2.35s i oddalenie zrobimy na 5s". "Lądowanie" tutaj = faza zbliżania
    /// W TRAKCIE lotu (`shrinkPhaseSeconds`), NIE osobny, dyskretny zjazd po
    /// zakończeniu pętli kroków (ten zostaje 2.5s, niezmieniony — patrz
    /// `TravelLiveMapView`/`TravelMapboxLiveView`). "Postój" (pokazanie karty
    /// z nazwą miasta) to również osobna wartość, ustawiana tam, nie tutaj.
    /// `legStepCount(baseStepSeconds:)` i `frameState`'s domyślne
    /// `growPhase`/`shrinkStart` są liczone z TYCH sekund, żeby zmiana
    /// jednej wartości nie wymagała ręcznego przeliczania proporcji.
    static let growPhaseSeconds: Double = 5.0
    static let cruisePhaseSeconds: Double = 1.35
    static let shrinkPhaseSeconds: Double = 2.35
    static var legTotalSeconds: Double { growPhaseSeconds + cruisePhaseSeconds + shrinkPhaseSeconds }
    private static var growPhaseFraction: Double { growPhaseSeconds / legTotalSeconds }
    private static var shrinkStartFraction: Double { 1 - shrinkPhaseSeconds / legTotalSeconds }

    /// Liczba kroków pętli animacji jednego odcinka, przy danym czasie
    /// pojedynczego kroku (`baseStepSeconds`, zależnym od `speedMultiplier`
    /// w miejscu wywołania) — tak żeby CAŁY odcinek trwał `legTotalSeconds`
    /// niezależnie od tego jak drobno jest próbkowany.
    static func legStepCount(baseStepSeconds: Double) -> Int {
        max(8, Int(legTotalSeconds / max(0.001, baseStepSeconds)))
    }

    /// Jeden wspólny stan klatki animacji — wołany identycznie z obu miejsc
    /// (podgląd + eksport), więc dystans/pochylenie/skala ikony nigdy się nie
    /// rozjadą między nimi. Blenduje między bliskim `establishingDistance`
    /// (start/koniec odcinka) a przelotowym `base` (środek) przez
    /// `distanceEnvelope` — patrz komentarz przy `establishingDistance`.
    ///
    /// `transport: .plane` → OMIJA CAŁĄ powyższą obwiednię, wraca do
    /// PIERWOTNEGO, stałego `ceilingDistance` (dawny `globeDistance`) przez
    /// CAŁY odcinek — user 01.08.2026, po obejrzeniu starego nagrania
    /// (28.06.2026) obok dzisiejszego: "napewno loty będą przeważały...
    /// zostaną tak jak na tym filmiku... jeśli jest inny środek transportu
    /// będzie przybliżenie". Loty to jedyny środek transportu, przy którym
    /// zgłaszano problem "wystrzelonego samolotu" — cała dzisiejsza obwiednia
    /// (grow/cruise/shrink) była próbą OSWOJENIA zmian zoomu, ale zero zmian
    /// zoomu (jak w pierwszym silniku, sprzed `TravelCinematics`) usuwa
    /// problem u źródła. Pozostałe środki transportu (car/train/boat/cruise/
    /// hiking) ZATRZYMUJĄ adaptacyjną obwiednię — tam zgłoszony wcześniej
    /// problem był odwrotny ("niewidoczny ruch" przy stałym, szerokim
    /// dystansie), więc przybliżenie zostaje.
    static func frameState(progress: Double, legDistanceKm: Double, transport: TransportMode, growPhase: Double = growPhaseFraction, shrinkStart: Double = shrinkStartFraction) -> FrameState {
        // 04.08.2026 (user, po pierwszej próbie z pełną obwiednią zoomu dla
        // długich lotów: "bardzo klatkuje") — KAŻDA zmiana `distance` to dla
        // MapKit inny poziom kafelków, więc płynna obwiednia zoomu (jak
        // reszta środków transportu) wymaga ciągłego doładowywania nowych
        // kafelków W TRAKCIE bardzo szybkiego, wielotysiąckilometrowego
        // przelotu — stąd klatkowanie nawet z dodatkowym prefetchem. Dystans
        // KAMERY dla WSZYSTKICH lotów (krótkich i długich) zostaje więc
        // stały (`ceilingDistance`, zero zmian zoomu = zero dodatkowych
        // poziomów kafelków do doładowania w locie) — to co faktycznie różni
        // krótkie i długie loty to WYŁĄCZNIE środek kadru (`legCameraCenter`
        // w `TravelLiveMapView`/`TravelMapVideoRenderer`: stały środek trasy
        // dla krótkich, podążający za samolotem dla długich powyżej
        // `longFlightFollowThresholdKm`) — czysty PAN bez zoomu jest dla
        // MapKit dużo tańszy niż pan+zoom naraz.
        guard transport != .plane else {
            return FrameState(cameraDistance: ceilingDistance, cameraPitch: 0, iconScale: iconScale(progress: progress))
        }
        let base = baseCameraDistance(legDistanceKm: legDistanceKm)
        // Dla bardzo krótkich odcinków (`base` już bliski `floorDistance`)
        // "zbliżenie" nie może być SZERSZE niż sam przelot — stąd `min`.
        let closeDistance = min(base, establishingDistance)
        let envelope = distanceEnvelope(progress: progress, growPhase: growPhase, shrinkStart: shrinkStart)
        let distance = min(ceilingDistance, max(floorDistance, closeDistance + (base - closeDistance) * envelope))
        return FrameState(
            cameraDistance: distance,
            cameraPitch: cameraPitch(forDistance: distance),
            iconScale: iconScale(progress: progress)
        )
    }

    // MARK: - Przechył ikony pojazdu na zakrętach ("banking", przybliżone)

    /// Różnica namiaru (stopnie, -180...180) między dwoma kolejnymi krokami —
    /// im większa, tym ostrzejszy zakręt.
    static func turnDelta(previousHeading: Double, currentHeading: Double) -> Double {
        var delta = (currentHeading - previousHeading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// Surowy (nieostudzony) kąt przechyłu na podstawie ostrości zakrętu —
    /// UWAGA: to jest DODATKOWY obrót, doklejany do istniejącego obrotu z
    /// namiaru, NIGDY nie wraca do samego `bearing`/namiaru przekazywanego do
    /// `VehicleIconSet.resolve` (ta funkcja wybiera asset left/right/top po
    /// progach 45°/135°/225°/315° — przechył zmieszany z namiarem mógłby
    /// przeskoczyć próg i przełączyć grafikę w połowie zakrętu).
    static func rawLeanDegrees(previousHeading: Double?, currentHeading: Double, gain: Double = 0.5, maxLean: Double = 15) -> Double {
        guard let previousHeading else { return 0 }
        let delta = turnDelta(previousHeading: previousHeading, currentHeading: currentHeading)
        return max(-maxLean, min(maxLean, delta * gain))
    }

    /// Wygładzenie wykładnicze (EMA) na wierzchu ograniczenia — prawdziwe
    /// trasy z `MKDirections` mają dużo małokątowych punktów, więc sam clamp
    /// bez wygładzenia dawałby drganie klatka-po-klatce.
    static func smoothedLean(previous: Double, target: Double, factor: Double = 0.35) -> Double {
        previous + (target - previous) * factor
    }
}
