import Foundation
import CoreLocation

/// Uproszczone granice państw (Natural Earth 50m, domena publiczna) do
/// podświetlania odwiedzonych krajów na plakacie "My Travel Journey"
/// (12.09.2026, feedback narzeczonej usera: "mapa jest zbyt pusta...
/// podświetlone kraje = ogólna historia podróżowania, pinezki = konkretne
/// wspomnienia" — Warstwa 1 z jej systemu). Dane w
/// `WorldCountryBoundaries.json` (bundle resource w tym samym folderze) —
/// skonwertowane z Natural Earth: tylko kod ISO A2 + nazwa + geometria,
/// współrzędne zaokrąglone do 3 miejsc (~110m, wystarczające dla małej
/// mapy na plakacie), bez zbędnych atrybutów Natural Earth — 237 krajów/
/// terytoriów w ~1.6MB.
///
/// 12.09.2026: pierwotnie użyta rozdzielczość 110m (175 krajów) — user
/// słusznie zapytał "co jeśli tester ma w bazie kraj którego nie mamy".
/// Sprawdzone: 110m brakowało 76 z 249 kodów ISO, w tym bardzo
/// prawdopodobne cele podróży (Malta, Singapur, Hong Kong, Monako,
/// Liechtenstein, San Marino, Malediwy, Bahrajn). Przejście na 50m
/// zredukowało brakujące kody do 13 (głównie bezludne wyspy i francuskie
/// terytoria zamorskie geokodowane zwykle jako Francja) — świadomie
/// zaakceptowana reszta, kolejny skok rozdzielczości (10m) kosztowałby
/// dużo więcej miejsca za marginalną poprawę.
/// Jeśli kraj z `SavedStop.countryCode` NIE ma odpowiednika w `all` (ten
/// pozostały margines LUB literówka/nietypowy kod z geokodowania Apple) —
/// `renderMapSnapshot` po prostu POMIJA podświetlenie tego kraju, appka się
/// nie wywala, kraj wygląda tak jak nieodwiedzony (baza mapy `.mutedStandard`
/// i tak jest blado-kremowa). Ciche pominięcie, nie awaria.
enum WorldCountryBoundaries {
    struct Country {
        let code: String
        let name: String
        /// Każdy element to jeden POLIGON kraju (rozdzielone terytoria —
        /// wyspy, eksklawy — mają kilka), każdy poligon to lista pierścieni
        /// (pierwszy = zewnętrzna granica, kolejne = dziury), każdy
        /// pierścień to lista współrzędnych w kolejności GeoJSON.
        let polygons: [[[CLLocationCoordinate2D]]]
    }

    /// Wczytane raz, leniwie (statyczna stała) — parsowanie trwa
    /// kilkadziesiąt ms, nie ma sensu robić tego przy każdym renderze
    /// plakatu. Klucz: kod ISO A2 (ten sam co `SavedStop.countryCode`).
    static let all: [String: Country] = load()

    private static func load() -> [String: Country] {
        guard let url = Bundle.main.url(forResource: "WorldCountryBoundaries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var result: [String: Country] = [:]
        for entry in raw {
            guard let code = entry["c"] as? String,
                  let name = entry["n"] as? String,
                  let polysRaw = entry["p"] as? [[[[Double]]]] else { continue }
            let polygons: [[[CLLocationCoordinate2D]]] = polysRaw.map { poly in
                poly.map { ring in
                    ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                }
            }
            result[code] = Country(code: code, name: name, polygons: polygons)
        }
        return result
    }
}
