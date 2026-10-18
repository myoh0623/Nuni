import Foundation

enum BrightnessVerificationResult: Equatable {
    case matches
    case differs
    case unavailable
}

enum AdaptiveMath {
    static func clamp(_ value: Double, min lower: Double = 0, max upper: Double = 1) -> Double {
        guard !value.isNaN else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }

    static func quantizedBrightness(_ value: Double) -> Double {
        (clamp(value) * 1_000).rounded() / 1_000
    }

    static func logarithmicLux(_ lux: Double, minimumLux: Double, maximumLux: Double) -> Double {
        let low = max(0.01, minimumLux)
        let high = max(low + 0.01, maximumLux)
        let bounded = clamp(lux, min: low, max: high)
        return (log10(bounded) - log10(low)) / (log10(high) - log10(low))
    }

    static func displayBrightness(base: Double, adjustment: Double) -> Double {
        clamp(base + adjustment)
    }

    static func verifyBrightness(
        requested: Double,
        observed: Double?,
        tolerance: Double = 0.03
    ) -> BrightnessVerificationResult {
        guard let observed, observed.isFinite else { return .unavailable }
        return abs(clamp(requested) - clamp(observed)) <= max(0, tolerance)
            ? .matches : .differs
    }

    static func clockBrightness(
        minute: Int,
        wakeMinute: Int,
        sleepMinute: Int,
        night: Double,
        day: Double,
        transitionMinutes: Int = 90
    ) -> Double {
        let minute = ((minute % 1440) + 1440) % 1440
        let wake = ((wakeMinute % 1440) + 1440) % 1440
        let sleep = ((sleepMinute % 1440) + 1440) % 1440

        let sinceWake = (minute - wake + 1440) % 1440
        let daylightLength = (sleep - wake + 1440) % 1440
        guard daylightLength > 0 else { return night }
        let transition = min(max(1, transitionMinutes), max(1, daylightLength / 2))
        if sinceWake <= daylightLength {
            if sinceWake < transition {
                return night + ((day - night) * Double(sinceWake) / Double(transition))
            }
            let untilSleep = daylightLength - sinceWake
            if untilSleep < transition {
                return night + ((day - night) * Double(untilSleep) / Double(transition))
            }
            return day
        }
        return night
    }
}
