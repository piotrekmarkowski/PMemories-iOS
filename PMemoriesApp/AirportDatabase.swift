import Foundation
import CoreLocation

/// Baza dużych/średnich lotnisk świata z kodami IATA — user 30.07.2026:
/// "London (STN) → Lanzarote (ACE)" zamiast pełnych/skróconych nazw.
/// MapKit NIE udostępnia kodów IATA w publicznym API (sprawdzone) — appka
/// wpisuje kod jako TEKST wyszukiwania i dostaje trafienie, ale wynik
/// (`MKMapItem`) nie niesie kodu z powrotem. Ta lista to RĘCZNIE
/// wyselekcjonowany zestaw znanych, jednoznacznych faktów (kod IATA + realne
/// miasto + przybliżone współrzędne największych lotnisk świata) — nie
/// zgadywanie, tylko powszechnie znane dane, ograniczone do lotnisk z
/// realnym ruchem pasażerskim (małe/regionalne lotniska świadomie
/// pominięte — dla nich appka cicho wraca do zwykłego skracania nazwy,
/// `CityGeocoder.shortenedAirportName`, zero regresji).
enum AirportDatabase {
    struct Airport {
        let iata: String
        let city: String
        let latitude: Double
        let longitude: Double
    }

    /// Promień dopasowania — lotniska bywają kilkanaście km od miasta,
    /// któremu "służą" (np. Stansted ~60km od centrum Londynu, więc próg
    /// musi być hojny, ale nie tak duży żeby łapać niewłaściwe lotnisko w
    /// gęsto zaludnionych regionach).
    private static let maxMatchDistanceKm: Double = 25

    static func nearest(to coordinate: CLLocationCoordinate2D) -> Airport? {
        var best: (airport: Airport, distance: Double)?
        for airport in airports {
            let distance = RouteProvider.straightDistanceKm(
                from: coordinate,
                to: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
            )
            guard distance <= maxMatchDistanceKm else { continue }
            if best == nil || distance < best!.distance {
                best = (airport, distance)
            }
        }
        return best?.airport
    }

    // MARK: - Europa

    private static let europe: [Airport] = [
        Airport(iata: "LHR", city: "London", latitude: 51.4700, longitude: -0.4543),
        Airport(iata: "LGW", city: "London", latitude: 51.1537, longitude: -0.1821),
        Airport(iata: "STN", city: "London", latitude: 51.8860, longitude: 0.2389),
        Airport(iata: "LTN", city: "London", latitude: 51.8747, longitude: -0.3683),
        Airport(iata: "LCY", city: "London", latitude: 51.5053, longitude: 0.0553),
        Airport(iata: "MAN", city: "Manchester", latitude: 53.3537, longitude: -2.2750),
        Airport(iata: "EDI", city: "Edinburgh", latitude: 55.9500, longitude: -3.3725),
        Airport(iata: "GLA", city: "Glasgow", latitude: 55.8642, longitude: -4.4331),
        Airport(iata: "BHX", city: "Birmingham", latitude: 52.4539, longitude: -1.7480),
        Airport(iata: "BRS", city: "Bristol", latitude: 51.3827, longitude: -2.7191),
        Airport(iata: "DUB", city: "Dublin", latitude: 53.4213, longitude: -6.2701),
        Airport(iata: "CDG", city: "Paris", latitude: 49.0097, longitude: 2.5479),
        Airport(iata: "ORY", city: "Paris", latitude: 48.7233, longitude: 2.3794),
        Airport(iata: "NCE", city: "Nice", latitude: 43.6584, longitude: 7.2159),
        Airport(iata: "LYS", city: "Lyon", latitude: 45.7256, longitude: 5.0811),
        Airport(iata: "MRS", city: "Marseille", latitude: 43.4393, longitude: 5.2214),
        Airport(iata: "TLS", city: "Toulouse", latitude: 43.6293, longitude: 1.3639),
        Airport(iata: "FRA", city: "Frankfurt", latitude: 50.0379, longitude: 8.5622),
        Airport(iata: "MUC", city: "Munich", latitude: 48.3538, longitude: 11.7861),
        Airport(iata: "BER", city: "Berlin", latitude: 52.3667, longitude: 13.5033),
        Airport(iata: "DUS", city: "Düsseldorf", latitude: 51.2895, longitude: 6.7668),
        Airport(iata: "HAM", city: "Hamburg", latitude: 53.6304, longitude: 9.9882),
        Airport(iata: "CGN", city: "Cologne", latitude: 50.8659, longitude: 7.1427),
        Airport(iata: "STR", city: "Stuttgart", latitude: 48.6899, longitude: 9.2220),
        Airport(iata: "AMS", city: "Amsterdam", latitude: 52.3105, longitude: 4.7683),
        Airport(iata: "BRU", city: "Brussels", latitude: 50.9014, longitude: 4.4844),
        Airport(iata: "CRL", city: "Brussels", latitude: 50.4592, longitude: 4.4525),
        Airport(iata: "ZRH", city: "Zurich", latitude: 47.4647, longitude: 8.5492),
        Airport(iata: "GVA", city: "Geneva", latitude: 46.2381, longitude: 6.1090),
        Airport(iata: "BSL", city: "Basel", latitude: 47.5900, longitude: 7.5291),
        Airport(iata: "VIE", city: "Vienna", latitude: 48.1103, longitude: 16.5697),
        Airport(iata: "FCO", city: "Rome", latitude: 41.8003, longitude: 12.2389),
        Airport(iata: "CIA", city: "Rome", latitude: 41.7994, longitude: 12.5949),
        Airport(iata: "MXP", city: "Milan", latitude: 45.6306, longitude: 8.7281),
        Airport(iata: "LIN", city: "Milan", latitude: 45.4451, longitude: 9.2767),
        Airport(iata: "BGY", city: "Milan", latitude: 45.6739, longitude: 9.7042),
        Airport(iata: "VCE", city: "Venice", latitude: 45.5053, longitude: 12.3519),
        Airport(iata: "NAP", city: "Naples", latitude: 40.8860, longitude: 14.2908),
        Airport(iata: "BLQ", city: "Bologna", latitude: 44.5354, longitude: 11.2887),
        Airport(iata: "PSA", city: "Pisa", latitude: 43.6839, longitude: 10.3927),
        Airport(iata: "CTA", city: "Catania", latitude: 37.4668, longitude: 15.0664),
        Airport(iata: "PMO", city: "Palermo", latitude: 38.1760, longitude: 13.0910),
        Airport(iata: "CAG", city: "Cagliari", latitude: 39.2515, longitude: 9.0543),
        Airport(iata: "MAD", city: "Madrid", latitude: 40.4936, longitude: -3.5668),
        Airport(iata: "BCN", city: "Barcelona", latitude: 41.2971, longitude: 2.0785),
        Airport(iata: "AGP", city: "Malaga", latitude: 36.6749, longitude: -4.4991),
        Airport(iata: "PMI", city: "Palma de Mallorca", latitude: 39.5517, longitude: 2.7388),
        Airport(iata: "IBZ", city: "Ibiza", latitude: 38.8729, longitude: 1.3731),
        Airport(iata: "ALC", city: "Alicante", latitude: 38.2822, longitude: -0.5582),
        Airport(iata: "VLC", city: "Valencia", latitude: 39.4893, longitude: -0.4816),
        Airport(iata: "SVQ", city: "Seville", latitude: 37.4180, longitude: -5.8931),
        Airport(iata: "BIO", city: "Bilbao", latitude: 43.3011, longitude: -2.9106),
        Airport(iata: "LPA", city: "Gran Canaria", latitude: 27.9319, longitude: -15.3866),
        Airport(iata: "TFS", city: "Tenerife", latitude: 28.0445, longitude: -16.5725),
        Airport(iata: "TFN", city: "Tenerife", latitude: 28.4827, longitude: -16.3415),
        Airport(iata: "ACE", city: "Lanzarote", latitude: 28.9455, longitude: -13.6052),
        Airport(iata: "FUE", city: "Fuerteventura", latitude: 28.4527, longitude: -13.8638),
        Airport(iata: "LIS", city: "Lisbon", latitude: 38.7813, longitude: -9.1359),
        Airport(iata: "OPO", city: "Porto", latitude: 41.2481, longitude: -8.6814),
        Airport(iata: "FAO", city: "Faro", latitude: 37.0144, longitude: -7.9659),
        Airport(iata: "FNC", city: "Madeira", latitude: 32.6979, longitude: -16.7745),
        Airport(iata: "ATH", city: "Athens", latitude: 37.9364, longitude: 23.9445),
        Airport(iata: "SKG", city: "Thessaloniki", latitude: 40.5197, longitude: 22.9709),
        Airport(iata: "HER", city: "Crete", latitude: 35.3397, longitude: 25.1803),
        Airport(iata: "CHQ", city: "Crete", latitude: 35.5317, longitude: 24.1497),
        Airport(iata: "RHO", city: "Rhodes", latitude: 36.4054, longitude: 28.0862),
        Airport(iata: "JTR", city: "Santorini", latitude: 36.3992, longitude: 25.4793),
        Airport(iata: "JMK", city: "Mykonos", latitude: 37.4351, longitude: 25.3481),
        Airport(iata: "CFU", city: "Corfu", latitude: 39.6019, longitude: 19.9117),
        Airport(iata: "KGS", city: "Kos", latitude: 36.7933, longitude: 27.0917),
        Airport(iata: "ZAG", city: "Zagreb", latitude: 45.7429, longitude: 16.0688),
        Airport(iata: "SPU", city: "Split", latitude: 43.5389, longitude: 16.2981),
        Airport(iata: "DBV", city: "Dubrovnik", latitude: 42.5614, longitude: 18.2682),
        Airport(iata: "LJU", city: "Ljubljana", latitude: 46.2237, longitude: 14.4576),
        Airport(iata: "SJJ", city: "Sarajevo", latitude: 43.8246, longitude: 18.3315),
        Airport(iata: "BEG", city: "Belgrade", latitude: 44.8184, longitude: 20.3091),
        Airport(iata: "SKP", city: "Skopje", latitude: 41.9616, longitude: 21.6214),
        Airport(iata: "TIA", city: "Tirana", latitude: 41.4147, longitude: 19.7206),
        Airport(iata: "PRN", city: "Pristina", latitude: 42.5728, longitude: 21.0358),
        Airport(iata: "SOF", city: "Sofia", latitude: 42.6952, longitude: 23.4062),
        Airport(iata: "VAR", city: "Varna", latitude: 43.2321, longitude: 27.8251),
        Airport(iata: "BOJ", city: "Burgas", latitude: 42.5696, longitude: 27.5152),
        Airport(iata: "OTP", city: "Bucharest", latitude: 44.5711, longitude: 26.0850),
        Airport(iata: "CLJ", city: "Cluj-Napoca", latitude: 46.7852, longitude: 23.6862),
        Airport(iata: "BUD", city: "Budapest", latitude: 47.4298, longitude: 19.2611),
        Airport(iata: "WAW", city: "Warsaw", latitude: 52.1657, longitude: 20.9671),
        Airport(iata: "WMI", city: "Warsaw", latitude: 52.4511, longitude: 20.6518),
        Airport(iata: "KRK", city: "Krakow", latitude: 50.0777, longitude: 19.7848),
        Airport(iata: "GDN", city: "Gdansk", latitude: 54.3776, longitude: 18.4662),
        Airport(iata: "WRO", city: "Wroclaw", latitude: 51.1027, longitude: 16.8858),
        Airport(iata: "POZ", city: "Poznan", latitude: 52.4210, longitude: 16.8263),
        Airport(iata: "KTW", city: "Katowice", latitude: 50.4743, longitude: 19.0800),
        Airport(iata: "RZE", city: "Rzeszow", latitude: 50.1100, longitude: 22.0190),
        Airport(iata: "LCJ", city: "Lodz", latitude: 51.7219, longitude: 19.3981),
        Airport(iata: "SZZ", city: "Szczecin", latitude: 53.5847, longitude: 14.9022),
        Airport(iata: "BZG", city: "Bydgoszcz", latitude: 53.0968, longitude: 17.9777),
        Airport(iata: "PRG", city: "Prague", latitude: 50.1008, longitude: 14.2600),
        Airport(iata: "BTS", city: "Bratislava", latitude: 48.1702, longitude: 17.2127),
        Airport(iata: "TLL", city: "Tallinn", latitude: 59.4133, longitude: 24.8328),
        Airport(iata: "RIX", city: "Riga", latitude: 56.9236, longitude: 23.9711),
        Airport(iata: "VNO", city: "Vilnius", latitude: 54.6341, longitude: 25.2858),
        Airport(iata: "CPH", city: "Copenhagen", latitude: 55.6180, longitude: 12.6560),
        Airport(iata: "OSL", city: "Oslo", latitude: 60.1976, longitude: 11.1004),
        Airport(iata: "BGO", city: "Bergen", latitude: 60.2934, longitude: 5.2181),
        Airport(iata: "TRD", city: "Trondheim", latitude: 63.4578, longitude: 10.9240),
        Airport(iata: "ARN", city: "Stockholm", latitude: 59.6519, longitude: 17.9186),
        Airport(iata: "GOT", city: "Gothenburg", latitude: 57.6628, longitude: 12.2798),
        Airport(iata: "HEL", city: "Helsinki", latitude: 60.3172, longitude: 24.9633),
        Airport(iata: "KEF", city: "Reykjavik", latitude: 63.9850, longitude: -22.6056),
        Airport(iata: "LUX", city: "Luxembourg", latitude: 49.6233, longitude: 6.2044),
        Airport(iata: "IST", city: "Istanbul", latitude: 41.2753, longitude: 28.7519),
        Airport(iata: "SAW", city: "Istanbul", latitude: 40.8986, longitude: 29.3092),
        Airport(iata: "AYT", city: "Antalya", latitude: 36.8987, longitude: 30.8005),
        Airport(iata: "ADB", city: "Izmir", latitude: 38.2924, longitude: 27.1568),
        Airport(iata: "ESB", city: "Ankara", latitude: 40.1281, longitude: 32.9951),
        Airport(iata: "SVO", city: "Moscow", latitude: 55.9736, longitude: 37.4125),
        Airport(iata: "DME", city: "Moscow", latitude: 55.4088, longitude: 37.9063),
        Airport(iata: "LED", city: "Saint Petersburg", latitude: 59.8003, longitude: 30.2625),
        Airport(iata: "KBP", city: "Kyiv", latitude: 50.3450, longitude: 30.8947),
    ]

    // MARK: - Ameryka Północna

    private static let northAmerica: [Airport] = [
        Airport(iata: "JFK", city: "New York", latitude: 40.6413, longitude: -73.7781),
        Airport(iata: "LGA", city: "New York", latitude: 40.7769, longitude: -73.8740),
        Airport(iata: "EWR", city: "New York", latitude: 40.6895, longitude: -74.1745),
        Airport(iata: "LAX", city: "Los Angeles", latitude: 33.9416, longitude: -118.4085),
        Airport(iata: "ORD", city: "Chicago", latitude: 41.9742, longitude: -87.9073),
        Airport(iata: "MDW", city: "Chicago", latitude: 41.7868, longitude: -87.7522),
        Airport(iata: "DFW", city: "Dallas", latitude: 32.8998, longitude: -97.0403),
        Airport(iata: "DEN", city: "Denver", latitude: 39.8561, longitude: -104.6737),
        Airport(iata: "SFO", city: "San Francisco", latitude: 37.6213, longitude: -122.3790),
        Airport(iata: "SEA", city: "Seattle", latitude: 47.4502, longitude: -122.3088),
        Airport(iata: "LAS", city: "Las Vegas", latitude: 36.0840, longitude: -115.1537),
        Airport(iata: "MIA", city: "Miami", latitude: 25.7959, longitude: -80.2870),
        Airport(iata: "MCO", city: "Orlando", latitude: 28.4312, longitude: -81.3081),
        Airport(iata: "ATL", city: "Atlanta", latitude: 33.6407, longitude: -84.4277),
        Airport(iata: "BOS", city: "Boston", latitude: 42.3656, longitude: -71.0096),
        Airport(iata: "IAD", city: "Washington", latitude: 38.9531, longitude: -77.4565),
        Airport(iata: "DCA", city: "Washington", latitude: 38.8512, longitude: -77.0402),
        Airport(iata: "PHX", city: "Phoenix", latitude: 33.4352, longitude: -112.0101),
        Airport(iata: "IAH", city: "Houston", latitude: 29.9902, longitude: -95.3368),
        Airport(iata: "PHL", city: "Philadelphia", latitude: 39.8744, longitude: -75.2424),
        Airport(iata: "AUS", city: "Austin", latitude: 30.1975, longitude: -97.6664),
        Airport(iata: "SAN", city: "San Diego", latitude: 32.7338, longitude: -117.1933),
        Airport(iata: "PDX", city: "Portland", latitude: 45.5898, longitude: -122.5951),
        Airport(iata: "SLC", city: "Salt Lake City", latitude: 40.7884, longitude: -111.9778),
        Airport(iata: "MSP", city: "Minneapolis", latitude: 44.8848, longitude: -93.2223),
        Airport(iata: "DTW", city: "Detroit", latitude: 42.2124, longitude: -83.3534),
        Airport(iata: "HNL", city: "Honolulu", latitude: 21.3187, longitude: -157.9224),
        Airport(iata: "YYZ", city: "Toronto", latitude: 43.6777, longitude: -79.6248),
        Airport(iata: "YVR", city: "Vancouver", latitude: 49.1967, longitude: -123.1815),
        Airport(iata: "YUL", city: "Montreal", latitude: 45.4706, longitude: -73.7408),
        Airport(iata: "YYC", city: "Calgary", latitude: 51.1315, longitude: -114.0106),
        Airport(iata: "MEX", city: "Mexico City", latitude: 19.4363, longitude: -99.0721),
        Airport(iata: "CUN", city: "Cancun", latitude: 21.0365, longitude: -86.8770),
    ]

    // MARK: - Ameryka Południowa

    private static let southAmerica: [Airport] = [
        Airport(iata: "GRU", city: "Sao Paulo", latitude: -23.4356, longitude: -46.4731),
        Airport(iata: "GIG", city: "Rio de Janeiro", latitude: -22.8090, longitude: -43.2506),
        Airport(iata: "EZE", city: "Buenos Aires", latitude: -34.8222, longitude: -58.5358),
        Airport(iata: "SCL", city: "Santiago", latitude: -33.3930, longitude: -70.7858),
        Airport(iata: "LIM", city: "Lima", latitude: -12.0219, longitude: -77.1143),
        Airport(iata: "BOG", city: "Bogota", latitude: 4.7016, longitude: -74.1469),
        Airport(iata: "UIO", city: "Quito", latitude: -0.1292, longitude: -78.3575),
    ]

    // MARK: - Azja i Oceania

    private static let asiaPacific: [Airport] = [
        Airport(iata: "HND", city: "Tokyo", latitude: 35.5494, longitude: 139.7798),
        Airport(iata: "NRT", city: "Tokyo", latitude: 35.7720, longitude: 140.3929),
        Airport(iata: "KIX", city: "Osaka", latitude: 34.4347, longitude: 135.2440),
        Airport(iata: "ICN", city: "Seoul", latitude: 37.4602, longitude: 126.4407),
        Airport(iata: "PEK", city: "Beijing", latitude: 40.0799, longitude: 116.6031),
        Airport(iata: "PVG", city: "Shanghai", latitude: 31.1443, longitude: 121.8083),
        Airport(iata: "HKG", city: "Hong Kong", latitude: 22.3080, longitude: 113.9185),
        Airport(iata: "TPE", city: "Taipei", latitude: 25.0797, longitude: 121.2342),
        Airport(iata: "BKK", city: "Bangkok", latitude: 13.6900, longitude: 100.7501),
        Airport(iata: "DMK", city: "Bangkok", latitude: 13.9126, longitude: 100.6067),
        Airport(iata: "HKT", city: "Phuket", latitude: 8.1132, longitude: 98.3169),
        Airport(iata: "SIN", city: "Singapore", latitude: 1.3644, longitude: 103.9915),
        Airport(iata: "KUL", city: "Kuala Lumpur", latitude: 2.7456, longitude: 101.7099),
        Airport(iata: "DPS", city: "Bali", latitude: -8.7481, longitude: 115.1671),
        Airport(iata: "CGK", city: "Jakarta", latitude: -6.1256, longitude: 106.6559),
        Airport(iata: "MNL", city: "Manila", latitude: 14.5086, longitude: 121.0194),
        Airport(iata: "SGN", city: "Ho Chi Minh City", latitude: 10.8188, longitude: 106.6520),
        Airport(iata: "HAN", city: "Hanoi", latitude: 21.2212, longitude: 105.8072),
        Airport(iata: "DEL", city: "Delhi", latitude: 28.5562, longitude: 77.1000),
        Airport(iata: "BOM", city: "Mumbai", latitude: 19.0896, longitude: 72.8656),
        Airport(iata: "GOI", city: "Goa", latitude: 15.3808, longitude: 73.8314),
        Airport(iata: "DXB", city: "Dubai", latitude: 25.2532, longitude: 55.3657),
        Airport(iata: "AUH", city: "Abu Dhabi", latitude: 24.4330, longitude: 54.6511),
        Airport(iata: "DOH", city: "Doha", latitude: 25.2731, longitude: 51.6081),
        Airport(iata: "TLV", city: "Tel Aviv", latitude: 32.0114, longitude: 34.8867),
        Airport(iata: "AMM", city: "Amman", latitude: 31.7226, longitude: 35.9932),
        Airport(iata: "CAI", city: "Cairo", latitude: 30.1219, longitude: 31.4056),
        Airport(iata: "RUH", city: "Riyadh", latitude: 24.9576, longitude: 46.6988),
        Airport(iata: "JED", city: "Jeddah", latitude: 21.6796, longitude: 39.1565),
        Airport(iata: "SYD", city: "Sydney", latitude: -33.9399, longitude: 151.1753),
        Airport(iata: "MEL", city: "Melbourne", latitude: -37.6690, longitude: 144.8410),
        Airport(iata: "BNE", city: "Brisbane", latitude: -27.3842, longitude: 153.1175),
        Airport(iata: "PER", city: "Perth", latitude: -31.9385, longitude: 115.9672),
        Airport(iata: "AKL", city: "Auckland", latitude: -37.0082, longitude: 174.7850),
    ]

    // MARK: - Afryka

    private static let africa: [Airport] = [
        Airport(iata: "JNB", city: "Johannesburg", latitude: -26.1392, longitude: 28.2460),
        Airport(iata: "CPT", city: "Cape Town", latitude: -33.9715, longitude: 18.6021),
        Airport(iata: "NBO", city: "Nairobi", latitude: -1.3192, longitude: 36.9278),
        Airport(iata: "ADD", city: "Addis Ababa", latitude: 8.9779, longitude: 38.7993),
        Airport(iata: "LOS", city: "Lagos", latitude: 6.5774, longitude: 3.3212),
        Airport(iata: "CMN", city: "Casablanca", latitude: 33.3675, longitude: -7.5900),
        Airport(iata: "RAK", city: "Marrakech", latitude: 31.6069, longitude: -8.0363),
        Airport(iata: "TUN", city: "Tunis", latitude: 36.8510, longitude: 10.2272),
        Airport(iata: "ALG", city: "Algiers", latitude: 36.6910, longitude: 3.2154),
    ]

    static let airports: [Airport] = europe + northAmerica + southAmerica + asiaPacific + africa
}
