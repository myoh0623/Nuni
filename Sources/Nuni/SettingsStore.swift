import Combine
import Foundation

enum AdaptiveModeKind: String, CaseIterable, Sendable {
    case manual
    case sync
    case sensor
    case location
    case clock

    var title: String {
        switch self {
        case .manual: "Manual"
        case .sync: "Sync"
        case .sensor: "Sensor"
        case .location: "Location"
        case .clock: "Clock"
        }
    }

    var symbolName: String {
        switch self {
        case .manual: "slider.horizontal.3"
        case .sync: "rectangle.2.swap"
        case .sensor: "sun.max"
        case .location: "location"
        case .clock: "clock"
        }
    }

    var detail: String {
        switch self {
        case .manual: "Use a fixed brightness you choose."
        case .sync: "Follow the built-in display brightness."
        case .sensor: "Adapt to the ambient light sensor."
        case .location: "Adapt to the sun at your location."
        case .clock: "Use daytime and nighttime brightness."
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let mode = "nuni.mode"
        static let manualBrightness = "nuni.manualBrightness"
        static let minimumBrightness = "nuni.minimumBrightness"
        static let maximumBrightness = "nuni.maximumBrightness"
        static let minimumLux = "nuni.minimumLux"
        static let maximumLux = "nuni.maximumLux"
        static let latitude = "nuni.latitude"
        static let longitude = "nuni.longitude"
        static let wakeMinute = "nuni.wakeMinute"
        static let sleepMinute = "nuni.sleepMinute"
        static let preferHardware = "nuni.preferHardware"
        static let refreshSeconds = "nuni.refreshSeconds"
        static let displayAdjustments = "nuni.displayAdjustments"

        static let legacyMappings = [
            (mode, "community.mode"),
            (manualBrightness, "community.manualBrightness"),
            (minimumBrightness, "community.minimumBrightness"),
            (maximumBrightness, "community.maximumBrightness"),
            (minimumLux, "community.minimumLux"),
            (maximumLux, "community.maximumLux"),
            (latitude, "community.latitude"),
            (longitude, "community.longitude"),
            (wakeMinute, "community.wakeMinute"),
            (sleepMinute, "community.sleepMinute"),
            (preferHardware, "community.preferHardware"),
            (refreshSeconds, "community.refreshSeconds"),
            (displayAdjustments, "community.displayAdjustments"),
        ]
    }

    private let defaults: UserDefaults

    @Published var mode: AdaptiveModeKind {
        didSet { if mode != oldValue { defaults.set(mode.rawValue, forKey: Key.mode) } }
    }
    @Published var manualBrightness: Double {
        didSet { if manualBrightness != oldValue { defaults.set(manualBrightness, forKey: Key.manualBrightness) } }
    }
    @Published var minimumBrightness: Double {
        didSet { if minimumBrightness != oldValue { defaults.set(minimumBrightness, forKey: Key.minimumBrightness) } }
    }
    @Published var maximumBrightness: Double {
        didSet { if maximumBrightness != oldValue { defaults.set(maximumBrightness, forKey: Key.maximumBrightness) } }
    }
    @Published var minimumLux: Double {
        didSet { if minimumLux != oldValue { defaults.set(minimumLux, forKey: Key.minimumLux) } }
    }
    @Published var maximumLux: Double {
        didSet { if maximumLux != oldValue { defaults.set(maximumLux, forKey: Key.maximumLux) } }
    }
    @Published var latitude: Double {
        didSet { if latitude != oldValue { defaults.set(latitude, forKey: Key.latitude) } }
    }
    @Published var longitude: Double {
        didSet { if longitude != oldValue { defaults.set(longitude, forKey: Key.longitude) } }
    }
    @Published var wakeMinute: Int {
        didSet { if wakeMinute != oldValue { defaults.set(wakeMinute, forKey: Key.wakeMinute) } }
    }
    @Published var sleepMinute: Int {
        didSet { if sleepMinute != oldValue { defaults.set(sleepMinute, forKey: Key.sleepMinute) } }
    }
    @Published var preferHardware: Bool {
        didSet { if preferHardware != oldValue { defaults.set(preferHardware, forKey: Key.preferHardware) } }
    }
    @Published var refreshSeconds: Double {
        didSet { if refreshSeconds != oldValue { defaults.set(refreshSeconds, forKey: Key.refreshSeconds) } }
    }
    @Published private(set) var displayAdjustments: [String: Double] {
        didSet { if displayAdjustments != oldValue { defaults.set(displayAdjustments, forKey: Key.displayAdjustments) } }
    }

    init(defaults: UserDefaults = .standard) {
        Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        self.defaults = defaults
        mode = AdaptiveModeKind(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .manual
        manualBrightness = defaults.object(forKey: Key.manualBrightness) as? Double ?? 0.75
        minimumBrightness = defaults.object(forKey: Key.minimumBrightness) as? Double ?? 0.18
        maximumBrightness = defaults.object(forKey: Key.maximumBrightness) as? Double ?? 0.9
        minimumLux = defaults.object(forKey: Key.minimumLux) as? Double ?? 1
        maximumLux = defaults.object(forKey: Key.maximumLux) as? Double ?? 600
        latitude = defaults.object(forKey: Key.latitude) as? Double ?? 37.5665
        longitude = defaults.object(forKey: Key.longitude) as? Double ?? 126.978
        wakeMinute = defaults.object(forKey: Key.wakeMinute) as? Int ?? 8 * 60
        sleepMinute = defaults.object(forKey: Key.sleepMinute) as? Int ?? 20 * 60
        preferHardware = defaults.object(forKey: Key.preferHardware) as? Bool ?? true
        refreshSeconds = defaults.object(forKey: Key.refreshSeconds) as? Double ?? 2
        displayAdjustments = (defaults.dictionary(forKey: Key.displayAdjustments) ?? [:]).compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        }
    }

    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        let legacyBundleIdentifier = "community.lunar.opensource"
        guard let legacyDomain = defaults.persistentDomain(forName: legacyBundleIdentifier) else { return }

        for (newKey, legacyKey) in Key.legacyMappings where defaults.object(forKey: newKey) == nil {
            if let value = legacyDomain[legacyKey] {
                defaults.set(value, forKey: newKey)
            }
        }
    }

    var boundedMinimumBrightness: Double { AdaptiveMath.clamp(minimumBrightness, min: 0.05, max: 0.5) }
    var boundedMaximumBrightness: Double { max(boundedMinimumBrightness, AdaptiveMath.clamp(maximumBrightness)) }

    func effectiveBrightness(base: Double, displayKey: String) -> Double {
        AdaptiveMath.displayBrightness(base: base, adjustment: displayAdjustments[displayKey] ?? 0)
    }

    func setDisplayBrightness(_ brightness: Double, base: Double, displayKey: String) {
        var updated = displayAdjustments
        let adjustment = AdaptiveMath.clamp(brightness) - AdaptiveMath.clamp(base)
        if abs(adjustment) < 0.005 {
            updated.removeValue(forKey: displayKey)
        } else {
            updated[displayKey] = AdaptiveMath.clamp(adjustment, min: -1, max: 1)
        }
        if updated != displayAdjustments {
            displayAdjustments = updated
        }
    }

    func resetDisplayAdjustment(displayKey: String) {
        var updated = displayAdjustments
        updated.removeValue(forKey: displayKey)
        if updated != displayAdjustments {
            displayAdjustments = updated
        }
    }

    func resetAllDisplayAdjustments() {
        if !displayAdjustments.isEmpty {
            displayAdjustments = [:]
        }
    }
}
