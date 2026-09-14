import Foundation

/// Standardowy wzór wschodu/zachodu słońca ("Sunrise equation" — Almanac
/// for Computers 1990 / powszechnie używany w kalkulatorach NOAA), liczony
/// LOKALNIE i offline — bez zależności od sieci (13.09.2026, użyte w
/// `TravelJourneyPosterView` do wyboru dzień/noc mapy plakatu, tak jak
/// systemowy "Automatyczny" tryb wyglądu iOS, tylko bez publicznego API do
/// tego na iOS). Dokładność ~1-2 minuty — więcej niż wystarczające do
/// wyboru stylu mapy, nie do nawigacji.
enum SolarTime {
    /// Zwraca `nil` w dniach polarnych (słońce cały czas nad/pod horyzontem
    /// — `cosH` poza zakresem -1...1), wołający ma wtedy własny fallback.
    static func sunriseSunset(latitude: Double, longitude: Double, date: Date, calendar: Calendar = .current) -> (sunrise: Date, sunset: Date)? {
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        guard let sunrise = calculate(isSunrise: true, dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, date: date),
              let sunset = calculate(isSunrise: false, dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, date: date)
        else { return nil }
        return (sunrise, sunset)
    }

    private static func calculate(isSunrise: Bool, dayOfYear: Int, latitude: Double, longitude: Double, date: Date) -> Date? {
        // Oficjalny zenit wschodu/zachodu (uwzględnia refrakcję atmosferyczną
        // + promień tarczy słonecznej) — standardowa stała z algorytmu.
        let zenith = 90.833
        let lngHour = longitude / 15.0
        let t = Double(dayOfYear) + ((isSunrise ? 6.0 : 18.0) - lngHour) / 24.0

        let meanAnomaly = (0.9856 * t) - 3.289
        var trueLongitude = meanAnomaly + (1.916 * sinDeg(meanAnomaly)) + (0.020 * sinDeg(2 * meanAnomaly)) + 282.634
        trueLongitude = normalize360(trueLongitude)

        var rightAscension = atanDeg(0.91764 * tanDeg(trueLongitude))
        rightAscension = normalize360(rightAscension)
        // RA musi być w tej samej "ćwiartce" co L (standardowy krok algorytmu).
        let lQuadrant = floor(trueLongitude / 90.0) * 90.0
        let raQuadrant = floor(rightAscension / 90.0) * 90.0
        rightAscension = (rightAscension + (lQuadrant - raQuadrant)) / 15.0

        let sinDeclination = 0.39782 * sinDeg(trueLongitude)
        let cosDeclination = cosDeg(asinDeg(sinDeclination))

        let cosH = (cosDeg(zenith) - (sinDeclination * sinDeg(latitude))) / (cosDeclination * cosDeg(latitude))
        guard cosH >= -1, cosH <= 1 else { return nil }

        let hourAngle = (isSunrise ? 360 - acosDeg(cosH) : acosDeg(cosH)) / 15.0
        let localMeanTime = hourAngle + rightAscension - (0.06571 * t) - 6.622

        var utcHours = localMeanTime - lngHour
        utcHours = utcHours.truncatingRemainder(dividingBy: 24)
        if utcHours < 0 { utcHours += 24 }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let hour = Int(utcHours)
        let minuteFraction = (utcHours - Double(hour)) * 60
        components.hour = hour
        components.minute = Int(minuteFraction)
        components.second = Int((minuteFraction - Double(Int(minuteFraction))) * 60)
        return utcCalendar.date(from: components)
    }

    private static func normalize360(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    private static func sinDeg(_ degrees: Double) -> Double { sin(degrees * .pi / 180) }
    private static func cosDeg(_ degrees: Double) -> Double { cos(degrees * .pi / 180) }
    private static func tanDeg(_ degrees: Double) -> Double { tan(degrees * .pi / 180) }
    private static func asinDeg(_ value: Double) -> Double { asin(value) * 180 / .pi }
    private static func acosDeg(_ value: Double) -> Double { acos(value) * 180 / .pi }
    private static func atanDeg(_ value: Double) -> Double { atan(value) * 180 / .pi }
}
