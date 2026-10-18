import Foundation

@main
enum SmokeTests {
    static func main() {
        check(AdaptiveMath.clamp(-1) == 0, "clamp lower bound")
        check(AdaptiveMath.clamp(2) == 1, "clamp upper bound")
        check(AdaptiveMath.clamp(.nan, min: 0.2, max: 0.8) == 0.2, "clamp non-finite input")
        check(abs(AdaptiveMath.logarithmicLux(10, minimumLux: 1, maximumLux: 100) - 0.5) < 0.0001, "lux mapping")
        check(AdaptiveMath.logarithmicLux(0, minimumLux: 1, maximumLux: 100) == 0, "lux lower bound")
        check(AdaptiveMath.logarithmicLux(1_000, minimumLux: 1, maximumLux: 100) == 1, "lux upper bound")
        check(AdaptiveMath.quantizedBrightness(0.50049) == 0.5, "brightness quantization down")
        check(AdaptiveMath.quantizedBrightness(0.50051) == 0.501, "brightness quantization up")
        check(abs(AdaptiveMath.displayBrightness(base: 0.65, adjustment: 0.15) - 0.8) < 0.0001, "display adjustment")
        check(AdaptiveMath.displayBrightness(base: 0.9, adjustment: 0.4) == 1, "display adjustment clamps high")
        check(AdaptiveMath.displayBrightness(base: 0.1, adjustment: -0.4) == 0, "display adjustment clamps low")
        check(
            AdaptiveMath.verifyBrightness(requested: 0.5, observed: 0.52) == .matches,
            "hardware brightness verification tolerance"
        )
        check(
            AdaptiveMath.verifyBrightness(requested: 0.5, observed: 0.7) == .differs,
            "hardware brightness verification mismatch"
        )
        check(
            AdaptiveMath.verifyBrightness(requested: 0.5, observed: nil) == .unavailable,
            "hardware brightness verification unavailable"
        )

        let noon = AdaptiveMath.clockBrightness(
            minute: 12 * 60,
            wakeMinute: 8 * 60,
            sleepMinute: 20 * 60,
            night: 0.2,
            day: 0.8
        )
        let midnight = AdaptiveMath.clockBrightness(
            minute: 0,
            wakeMinute: 8 * 60,
            sleepMinute: 20 * 60,
            night: 0.2,
            day: 0.8
        )
        check(abs(noon - 0.8) < 0.0001, "clock daytime")
        check(abs(midnight - 0.2) < 0.0001, "clock nighttime")
        let overnightDay = AdaptiveMath.clockBrightness(
            minute: 23 * 60,
            wakeMinute: 20 * 60,
            sleepMinute: 6 * 60,
            night: 0.2,
            day: 0.8
        )
        let overnightNight = AdaptiveMath.clockBrightness(
            minute: 12 * 60,
            wakeMinute: 20 * 60,
            sleepMinute: 6 * 60,
            night: 0.2,
            day: 0.8
        )
        check(abs(overnightDay - 0.8) < 0.0001, "clock schedule across midnight")
        check(abs(overnightNight - 0.2) < 0.0001, "clock night across midnight")
        let shortScheduleMidpoint = AdaptiveMath.clockBrightness(
            minute: 8 * 60 + 30,
            wakeMinute: 8 * 60,
            sleepMinute: 9 * 60,
            night: 0.2,
            day: 0.8
        )
        check(abs(shortScheduleMidpoint - 0.8) < 0.0001, "short clock schedule reaches daytime value")
        check(
            AdaptiveMath.clockBrightness(
                minute: 12 * 60,
                wakeMinute: 8 * 60,
                sleepMinute: 8 * 60,
                night: 0.2,
                day: 0.8
            ) == 0.2,
            "equal clock endpoints stay at night value"
        )

        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            fail("UTC time zone")
        }
        calendar.timeZone = utc
        guard let midnightDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0)),
            let noonDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))
        else {
            fail("solar test dates")
        }
        let midnightElevation = SolarCalculator.elevation(date: midnightDate, latitude: 0, longitude: 0, calendar: calendar)
        let noonElevation = SolarCalculator.elevation(date: noonDate, latitude: 0, longitude: 0, calendar: calendar)
        check(midnightElevation.isFinite && noonElevation.isFinite, "finite solar elevation")
        check(noonElevation > midnightElevation, "solar elevation")

        print("All Nuni smoke tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fail(name)
        }
    }

    private static func fail(_ name: String) -> Never {
        fputs("Failed: \(name)\n", stderr)
        exit(1)
    }
}
