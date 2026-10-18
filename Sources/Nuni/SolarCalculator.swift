import Foundation

enum SolarCalculator {
    /// Approximate solar elevation using NOAA's published fractional-year equations.
    static func elevation(date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents(in: calendar.timeZone, from: date)
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hour = Double(components.hour ?? 12)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)
        let decimalHour = hour + minute / 60 + second / 3600
        let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365

        let gamma = 2 * Double.pi / Double(daysInYear) * (day - 1 + (decimalHour - 12) / 24)
        let equationOfTime =
            229.18
            * (0.000075
                + 0.001868 * cos(gamma)
                - 0.032077 * sin(gamma)
                - 0.014615 * cos(2 * gamma)
                - 0.040849 * sin(2 * gamma))
        let declination =
            0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let timezoneHours = Double(calendar.timeZone.secondsFromGMT(for: date)) / 3600
        let timeOffset = equationOfTime + 4 * longitude - 60 * timezoneHours
        let trueSolarMinutes = (decimalHour * 60 + timeOffset).truncatingRemainder(dividingBy: 1440)
        let hourAngleDegrees = trueSolarMinutes / 4 - 180
        let hourAngle = hourAngleDegrees * Double.pi / 180
        let latitudeRadians = latitude * Double.pi / 180
        let cosineZenith =
            sin(latitudeRadians) * sin(declination)
            + cos(latitudeRadians) * cos(declination) * cos(hourAngle)
        let zenith = acos(AdaptiveMath.clamp(cosineZenith, min: -1, max: 1))
        return 90 - (zenith * 180 / Double.pi)
    }
}
