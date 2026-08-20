import Foundation

/// Wybiera, który z 3 wyciętych z moodboardu widoków pojazdu (right/left/top)
/// narysować dla danego kierunku jazdy (namiar w stopniach, 0 = północ),
/// zamiast obracać jedną płaską ikonę o dowolny kąt.
///
/// Zasada (ustalona wprost przez usera): jadąc w prawo używamy TYLKO widoku
/// "right" — bez zmiany obrazka podczas ruchu. Jadąc w lewo — tylko "left".
/// Widok "top" (z góry) jest jedynym, który można bezpiecznie swobodnie
/// obracać (rzut ortogonalny, bez zniekształcenia perspektywy), więc pokrywa
/// zarówno ruch "w górę" jak i "w dół" mapy.
enum VehicleIconSet {
    struct Resolved {
        let assetName: String
        let rotationDegrees: Double
    }

    /// Kąt (stopnie, 0 = góra obrazu), jaki domyślnie reprezentuje widok
    /// "top" danego pojazdu — zmierzony wizualnie per pojazd, bo nie każdy
    /// wygenerowany obrazek ma dziób skierowany "do góry" kadru.
    private static func topBaseAngle(for transport: TransportMode) -> Double {
        switch transport {
        case .plane: return 0    // dziób u góry
        case .train: return 0    // dziób (zaokrąglona kabina) u góry
        case .boat: return 0     // dziób u góry
        // 30.07.2026 — poprawione z 180 na 0. Zdjęcie assetu pokazuje
        // CZERWONE ŚWIATŁA (tylne) na DOLE kadru, nie reflektory — czyli
        // przód jest u GÓRY, tak samo jak plane/train/boat. Stara wartość
        // (180) była błędna od początku, ale niewidoczna przy poprzednim,
        // stałym dystansie kamery 12 000 km — ikonka kilkupikselowa nie
        // pozwalała rozróżnić przodu od tyłu. Dopiero adaptacyjny,
        // bliski zoom (`TravelCinematics`) uwidocznił błąd — user: "auto
        // jeździ tyłem".
        case .car: return 0
        case .cruise: return 270 // dziób po LEWEJ (widok poziomy, nie pionowy)
        // Wędrówka rysowana emoji (patrz `TravelMapAnimationView`/
        // `TravelMapVideoRenderer`), nigdy nie trafia tutaj — case istnieje
        // wyłącznie dla wyczerpującego switcha.
        case .hiking: return 0
        }
    }

    static func resolve(transport: TransportMode, bearing: Double) -> Resolved {
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let prefix = "Vehicle-\(transport.rawValue)-"

        // Samolot, pociąg, samochód: widoki z boku wyszły słabo wycięte i słabo
        // wyglądają w ruchu — dla tych pojazdów używamy WYŁĄCZNIE widoku z góry,
        // swobodnie obróconego do namiaru we WSZYSTKICH kierunkach (nie tylko
        // N/S jak dla pozostałych pojazdów, które zachowują schemat 3-widokowy).
        guard transport != .plane, transport != .train, transport != .car else {
            let rotation = normalized - topBaseAngle(for: transport)
            return Resolved(assetName: prefix + "top", rotationDegrees: rotation)
        }

        switch normalized {
        case 45..<135:
            // Wschód — widok "right" wprost, bez rotacji, bez zmiany podczas ruchu.
            return Resolved(assetName: prefix + "right", rotationDegrees: 0)
        case 225..<315:
            // Zachód — widok "left" wprost, bez rotacji.
            return Resolved(assetName: prefix + "left", rotationDegrees: 0)
        default:
            // Północ lub południe — widok z góry, swobodnie obrócony do namiaru.
            let rotation = normalized - topBaseAngle(for: transport)
            return Resolved(assetName: prefix + "top", rotationDegrees: rotation)
        }
    }
}
