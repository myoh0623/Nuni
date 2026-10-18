import Combine
import Foundation

@MainActor
final class AdaptiveEngine: ObservableObject {
    @Published private(set) var statusText = "Ready"

    let settings: SettingsStore
    let displayController: DisplayController

    private let ambientReader = AmbientLightReader()
    private var adaptiveTimer: Timer?
    private var systemBrightnessTimer: Timer?
    private var scheduledAdaptiveInterval: TimeInterval?
    private var systemBrightnessReadbackAllowedAfter = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    init(settings: SettingsStore, displayController: DisplayController) {
        self.settings = settings
        self.displayController = displayController

        settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isStarted else { return }
                self.updateAdaptiveTimerIfNeeded()
                self.applyNow()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        updateAdaptiveTimerIfNeeded()
        systemBrightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.synchronizeBuiltinBrightnessFromSystem() }
        }
        applyNow()
    }

    func stop() {
        isStarted = false
        adaptiveTimer?.invalidate()
        adaptiveTimer = nil
        scheduledAdaptiveInterval = nil
        systemBrightnessTimer?.invalidate()
        systemBrightnessTimer = nil
    }

    func applyNow(date: Date = Date()) {
        let result = targetBrightness(date: date)
        apply(brightness: result.value, status: result.status)
    }

    func setGlobalBrightness(_ brightness: Double) {
        let value = AdaptiveMath.clamp(
            AdaptiveMath.quantizedBrightness(brightness),
            min: settings.boundedMinimumBrightness,
            max: 1
        )
        if settings.mode != .manual {
            settings.mode = .manual
        }
        if abs(settings.manualBrightness - value) >= 0.001 {
            settings.manualBrightness = value
        }
        applyNow()
    }

    func setBrightness(_ brightness: Double, for display: ManagedDisplay) {
        let safeBrightness = AdaptiveMath.clamp(
            AdaptiveMath.quantizedBrightness(brightness),
            min: settings.boundedMinimumBrightness,
            max: 1
        )

        if settings.mode == .sync, display.isBuiltin {
            apply(
                brightness: safeBrightness,
                status: "Sync · source \(Int((safeBrightness * 100).rounded()))%"
            )
            return
        }

        let base = targetBrightness(date: Date()).value
        settings.setDisplayBrightness(safeBrightness, base: base, displayKey: display.persistentKey)
        applyNow()
    }

    func resetBrightness(for display: ManagedDisplay) {
        settings.resetDisplayAdjustment(displayKey: display.persistentKey)
        applyNow()
    }

    func matchAllDisplays() {
        settings.resetAllDisplayAdjustments()
        applyNow()
    }

    private func apply(brightness: Double, status: String) {
        let wroteHardware = displayController.apply(
            brightness: brightness,
            adjustments: effectiveDisplayAdjustments,
            minimumBrightness: settings.boundedMinimumBrightness,
            preferHardware: settings.preferHardware
        )
        if wroteHardware {
            // DisplayServices can briefly return the previous hardware value
            // after a write. Ignore that short stale-read window only when a
            // hardware write actually happened.
            systemBrightnessReadbackAllowedAfter = Date().addingTimeInterval(0.75)
        }
        if statusText != status {
            statusText = status
        }
    }

    private var effectiveDisplayAdjustments: [String: Double] {
        guard settings.mode == .sync,
            let builtIn = displayController.displays.first(where: \.isBuiltin)
        else { return settings.displayAdjustments }

        var adjustments = settings.displayAdjustments
        adjustments.removeValue(forKey: builtIn.persistentKey)
        return adjustments
    }

    private func updateAdaptiveTimerIfNeeded() {
        let needsPeriodicUpdates: Bool
        switch settings.mode {
        case .sensor, .location, .clock:
            needsPeriodicUpdates = true
        case .manual, .sync:
            needsPeriodicUpdates = false
        }

        guard needsPeriodicUpdates else {
            adaptiveTimer?.invalidate()
            adaptiveTimer = nil
            scheduledAdaptiveInterval = nil
            return
        }

        let interval = max(0.5, settings.refreshSeconds)
        guard adaptiveTimer == nil || scheduledAdaptiveInterval != interval else { return }
        adaptiveTimer?.invalidate()
        scheduledAdaptiveInterval = interval
        adaptiveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyNow() }
        }
    }

    private func synchronizeBuiltinBrightnessFromSystem(date: Date = Date()) {
        guard date >= systemBrightnessReadbackAllowedAfter,
            settings.preferHardware,
            let display = displayController.displays.first(where: \.isBuiltin),
            let actual = displayController.hardwareBrightness(for: display)
        else { return }

        let minimum = settings.boundedMinimumBrightness
        let safeActual = max(actual, minimum)
        if actual < minimum, settings.mode == .sync {
            apply(
                brightness: minimum,
                status: "Sync · limited to safety minimum \(Int((minimum * 100).rounded()))%"
            )
            return
        }

        let lastRequested =
            displayController.appliedBrightnessByDisplay[display.id]
            ?? displayController.lastAppliedBrightness
        guard abs(actual - lastRequested) >= 0.01 else { return }

        if settings.mode == .sync {
            applyNow(date: date)
            return
        }

        if settings.mode == .manual {
            settings.resetDisplayAdjustment(displayKey: display.persistentKey)
            if abs(settings.manualBrightness - safeActual) >= 0.001 {
                settings.manualBrightness = safeActual
            }
            applyNow(date: date)
            return
        }

        let base = targetBrightness(date: date).value
        settings.setDisplayBrightness(safeActual, base: base, displayKey: display.persistentKey)
        applyNow(date: date)
    }

    func targetBrightness(date: Date) -> (value: Double, status: String) {
        let minBrightness = settings.boundedMinimumBrightness
        let maxBrightness = settings.boundedMaximumBrightness

        switch settings.mode {
        case .manual:
            let value = AdaptiveMath.clamp(settings.manualBrightness, min: minBrightness, max: 1)
            return (value, "Manual · \(Int((value * 100).rounded()))%")

        case .sync:
            guard let display = displayController.displays.first(where: \.isBuiltin),
                let source = displayController.hardwareBrightness(for: display)
            else {
                let fallback = AdaptiveMath.clamp(settings.manualBrightness, min: minBrightness, max: 1)
                return (fallback, "Sync · no built-in source, using manual value")
            }
            let value = AdaptiveMath.clamp(source, min: minBrightness, max: maxBrightness)
            return (value, "Sync · source \(Int((source * 100).rounded()))%")

        case .sensor:
            guard let lux = ambientReader.read() else {
                let fallback = AdaptiveMath.clamp(settings.manualBrightness, min: minBrightness, max: 1)
                return (fallback, "Sensor · no ALS reading, using manual value")
            }
            let progress = AdaptiveMath.logarithmicLux(
                lux,
                minimumLux: settings.minimumLux,
                maximumLux: settings.maximumLux
            )
            let value = minBrightness + ((maxBrightness - minBrightness) * progress)
            return (value, "Sensor · \(lux.formatted(.number.precision(.fractionLength(0...1)))) lux")

        case .location:
            let elevation = SolarCalculator.elevation(
                date: date,
                latitude: settings.latitude,
                longitude: settings.longitude
            )
            let progress = AdaptiveMath.clamp((elevation + 6) / 51)
            let value = minBrightness + ((maxBrightness - minBrightness) * progress)
            return (value, "Location · sun \(elevation.formatted(.number.precision(.fractionLength(0...1))))°")

        case .clock:
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let value = AdaptiveMath.clockBrightness(
                minute: minute,
                wakeMinute: settings.wakeMinute,
                sleepMinute: settings.sleepMinute,
                night: minBrightness,
                day: maxBrightness
            )
            return (value, "Clock · \(String(format: "%02d:%02d", minute / 60, minute % 60))")
        }
    }
}
