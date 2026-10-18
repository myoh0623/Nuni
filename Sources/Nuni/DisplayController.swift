import AppKit
import CoreGraphics
import Foundation

struct ManagedDisplay: Equatable, Sendable {
    let id: CGDirectDisplayID
    let persistentKey: String
    let name: String
    let isBuiltin: Bool
}

@MainActor
final class GammaController {
    private struct GammaTable {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    private var originalTables: [CGDirectDisplayID: GammaTable] = [:]

    func setBrightness(_ brightness: Double, displayID: CGDirectDisplayID) -> Bool {
        let table: GammaTable
        if let stored = originalTables[displayID] {
            table = stored
        } else if let captured = capture(displayID: displayID) {
            originalTables[displayID] = captured
            table = captured
        } else {
            return false
        }

        let scale = Float(AdaptiveMath.clamp(brightness, min: 0.03, max: 1))
        let red = table.red.map { min(1, $0 * scale) }
        let green = table.green.map { min(1, $0 * scale) }
        let blue = table.blue.map { min(1, $0 * scale) }
        let result = red.withUnsafeBufferPointer { redBuffer in
            green.withUnsafeBufferPointer { greenBuffer in
                blue.withUnsafeBufferPointer { blueBuffer in
                    CGSetDisplayTransferByTable(
                        displayID,
                        UInt32(red.count),
                        redBuffer.baseAddress,
                        greenBuffer.baseAddress,
                        blueBuffer.baseAddress
                    )
                }
            }
        }
        return result == .success
    }

    func restoreAll() {
        for (displayID, table) in originalTables {
            restore(table, displayID: displayID)
        }
        originalTables.removeAll()
    }

    func restore(displayID: CGDirectDisplayID) {
        guard let table = originalTables.removeValue(forKey: displayID) else { return }
        restore(table, displayID: displayID)
    }

    private func capture(displayID: CGDirectDisplayID) -> GammaTable? {
        let capacity = max(2, CGDisplayGammaTableCapacity(displayID))
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0

        let result = red.withUnsafeMutableBufferPointer { redBuffer in
            green.withUnsafeMutableBufferPointer { greenBuffer in
                blue.withUnsafeMutableBufferPointer { blueBuffer in
                    CGGetDisplayTransferByTable(
                        displayID,
                        capacity,
                        redBuffer.baseAddress,
                        greenBuffer.baseAddress,
                        blueBuffer.baseAddress,
                        &sampleCount
                    )
                }
            }
        }
        guard result == .success, sampleCount > 1 else { return nil }
        return GammaTable(
            red: Array(red.prefix(Int(sampleCount))),
            green: Array(green.prefix(Int(sampleCount))),
            blue: Array(blue.prefix(Int(sampleCount)))
        )
    }

    private func restore(_ table: GammaTable, displayID: CGDirectDisplayID) {
        table.red.withUnsafeBufferPointer { redBuffer in
            table.green.withUnsafeBufferPointer { greenBuffer in
                table.blue.withUnsafeBufferPointer { blueBuffer in
                    _ = CGSetDisplayTransferByTable(
                        displayID,
                        UInt32(table.red.count),
                        redBuffer.baseAddress,
                        greenBuffer.baseAddress,
                        blueBuffer.baseAddress
                    )
                }
            }
        }
    }
}

@MainActor
final class DisplayOverlayController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func setBrightness(_ brightness: Double, displayID: CGDirectDisplayID) -> Bool {
        guard let screen = screen(displayID: displayID) else { return false }
        let darkness = CGFloat(1 - AdaptiveMath.clamp(brightness, min: 0.03, max: 1))
        guard darkness > 0.001 else {
            restore(displayID: displayID)
            return true
        }

        let window: NSWindow
        if let existingWindow = windows[displayID] {
            window = existingWindow
        } else {
            window = makeWindow(frame: screen.frame)
            windows[displayID] = window
            window.orderFrontRegardless()
        }
        window.setFrame(screen.frame, display: true)
        window.alphaValue = darkness
        return true
    }

    func restore(displayID: CGDirectDisplayID) {
        guard let window = windows.removeValue(forKey: displayID) else { return }
        window.orderOut(nil)
        window.close()
    }

    func restoreAll() {
        for displayID in Array(windows.keys) {
            restore(displayID: displayID)
        }
    }

    private func screen(displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // DisplayLink and some projector-style outputs mirror WindowServer's
        // shareable composition surface. A non-shareable window can therefore
        // be visible on a native display while being omitted from those outputs.
        window.sharingType = .readOnly
        return window
    }
}

@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var lastAppliedBrightness: Double = 1
    @Published private(set) var appliedBrightnessByDisplay: [CGDirectDisplayID: Double] = [:]
    @Published private(set) var controlMethods: [CGDirectDisplayID: String] = [:]

    private let systemBrightness = SystemDisplayBrightnessController()
    private let gamma = GammaController()
    private let overlay = DisplayOverlayController()
    private var lastWrittenBrightnessByDisplay: [CGDirectDisplayID: Double] = [:]
    private var lastHardwarePreference: Bool?
    private var hardwareVerificationTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var hardwareVerificationTokens: [CGDirectDisplayID: UUID] = [:]

    init() {
        refreshDisplays()
    }

    func refreshDisplays() {
        cancelHardwareVerification()
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displayIDs.count), &displayIDs, &count) == .success else { return }
        displayIDs = Array(displayIDs.prefix(Int(count)))
        let oldIDs = Set(displays.map(\.id))
        let screenPairs: [(CGDirectDisplayID, NSScreen)] = NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                return nil
            }
            return (id, screen)
        }
        let screensByID = Dictionary(uniqueKeysWithValues: screenPairs)
        var externalIndex = 0
        let refreshedDisplays = displayIDs.map { id in
            let builtin = CGDisplayIsBuiltin(id) != 0
            if !builtin { externalIndex += 1 }
            let name = screensByID[id]?.localizedName ?? (builtin ? "Built-in Display" : "Display \(externalIndex)")
            return ManagedDisplay(
                id: id,
                persistentKey: persistentKey(for: id),
                name: name,
                isBuiltin: builtin
            )
        }

        let activeIDs = Set(refreshedDisplays.map(\.id))
        for removedID in oldIDs.subtracting(activeIDs) {
            gamma.restore(displayID: removedID)
            overlay.restore(displayID: removedID)
        }
        if displays != refreshedDisplays {
            displays = refreshedDisplays
        }
        let activeControlMethods = controlMethods.filter { activeIDs.contains($0.key) }
        if controlMethods != activeControlMethods {
            controlMethods = activeControlMethods
        }
        let activeBrightness = appliedBrightnessByDisplay.filter { activeIDs.contains($0.key) }
        if appliedBrightnessByDisplay != activeBrightness {
            appliedBrightnessByDisplay = activeBrightness
        }
        // Screen geometry and the backing service can change while a display ID
        // stays the same. Revalidate each output after a display refresh.
        lastWrittenBrightnessByDisplay.removeAll(keepingCapacity: true)
    }

    @discardableResult
    func apply(
        brightness: Double,
        adjustments: [String: Double],
        minimumBrightness: Double,
        preferHardware: Bool
    ) -> Bool {
        let safeMinimum = AdaptiveMath.clamp(minimumBrightness, min: 0.05, max: 0.5)
        let baseBrightness = AdaptiveMath.clamp(
            AdaptiveMath.quantizedBrightness(brightness),
            min: safeMinimum,
            max: 1
        )
        if lastAppliedBrightness != baseBrightness {
            lastAppliedBrightness = baseBrightness
        }
        let updatedBrightness = Dictionary(
            uniqueKeysWithValues: displays.map { display in
                let brightness = AdaptiveMath.clamp(
                    AdaptiveMath.quantizedBrightness(
                        AdaptiveMath.displayBrightness(
                            base: baseBrightness,
                            adjustment: adjustments[display.persistentKey] ?? 0
                        )
                    ),
                    min: safeMinimum,
                    max: 1
                )
                return (display.id, brightness)
            })
        if appliedBrightnessByDisplay != updatedBrightness {
            appliedBrightnessByDisplay = updatedBrightness
        }

        let hardwarePreferenceChanged = lastHardwarePreference != preferHardware
        lastHardwarePreference = preferHardware
        var wroteBuiltInHardwareBrightness = false

        for display in displays {
            let brightness = appliedBrightnessByDisplay[display.id] ?? baseBrightness
            if !hardwarePreferenceChanged,
                let previous = lastWrittenBrightnessByDisplay[display.id],
                abs(previous - brightness) < 0.001,
                controlMethods[display.id] != nil
            {
                continue
            }

            let hardwareResult =
                preferHardware
                ? systemBrightness.setBrightness(brightness, displayID: display.id)
                : .failed
            if let hardwareMethod = hardwareResult.method {
                gamma.restore(displayID: display.id)
                overlay.restore(displayID: display.id)
                switch hardwareResult {
                case .verified:
                    setControlMethod(hardwareMethod.verifiedDescription, displayID: display.id)
                case .accepted:
                    setControlMethod(hardwareMethod.checkingDescription, displayID: display.id)
                    scheduleHardwareVerification(brightness: brightness, for: display, method: hardwareMethod)
                case .failed:
                    break
                }
                lastWrittenBrightnessByDisplay[display.id] = brightness
                if display.isBuiltin {
                    wroteBuiltInHardwareBrightness = true
                }
                continue
            }
            if applySoftware(brightness: brightness, to: display) {
                lastWrittenBrightnessByDisplay[display.id] = brightness
            } else {
                lastWrittenBrightnessByDisplay.removeValue(forKey: display.id)
            }
        }
        return wroteBuiltInHardwareBrightness
    }

    func hardwareBrightness(for display: ManagedDisplay) -> Double? {
        guard display.isBuiltin else { return nil }
        return systemBrightness.read(displayID: display.id)
    }

    func restoreSoftwareAdjustments() {
        cancelHardwareVerification()
        gamma.restoreAll()
        overlay.restoreAll()
        lastWrittenBrightnessByDisplay.removeAll()
        lastHardwarePreference = nil
        lastAppliedBrightness = 1
        appliedBrightnessByDisplay = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, 1) })
    }

    private func persistentKey(for displayID: CGDirectDisplayID) -> String {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }

    @discardableResult
    private func applySoftware(brightness: Double, to display: ManagedDisplay) -> Bool {
        if display.isBuiltin, gamma.setBrightness(brightness, displayID: display.id) {
            overlay.restore(displayID: display.id)
            setControlMethod("Software gamma", displayID: display.id)
            return true
        }

        gamma.restore(displayID: display.id)
        if overlay.setBrightness(brightness, displayID: display.id) {
            setControlMethod("Software overlay", displayID: display.id)
            return true
        } else {
            setControlMethod("Control unavailable", displayID: display.id)
            return false
        }
    }

    private func setControlMethod(_ method: String, displayID: CGDirectDisplayID) {
        guard controlMethods[displayID] != method else { return }
        controlMethods[displayID] = method
    }

    private func scheduleHardwareVerification(
        brightness: Double,
        for display: ManagedDisplay,
        method: HardwareBrightnessMethod
    ) {
        hardwareVerificationTasks[display.id]?.cancel()
        let token = UUID()
        hardwareVerificationTokens[display.id] = token
        hardwareVerificationTasks[display.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self,
                self.hardwareVerificationTokens[display.id] == token
            else { return }

            let verification = AdaptiveMath.verifyBrightness(
                requested: brightness,
                observed: self.systemBrightness.read(displayID: display.id)
            )
            switch verification {
            case .matches:
                self.setControlMethod(method.verifiedDescription, displayID: display.id)
            case .differs:
                if self.applySoftware(brightness: brightness, to: display) {
                    self.setControlMethod("Software overlay · hardware ignored change", displayID: display.id)
                }
            case .unavailable:
                self.setControlMethod(method.unverifiedDescription, displayID: display.id)
            }
            self.hardwareVerificationTasks.removeValue(forKey: display.id)
            self.hardwareVerificationTokens.removeValue(forKey: display.id)
        }
    }

    private func cancelHardwareVerification() {
        for task in hardwareVerificationTasks.values {
            task.cancel()
        }
        hardwareVerificationTasks.removeAll(keepingCapacity: true)
        hardwareVerificationTokens.removeAll(keepingCapacity: true)
    }
}

private extension HardwareBrightnessMethod {
    var verifiedDescription: String {
        switch self {
        case .nativeSystem: "Hardware · macOS System API"
        case .ioKit: "Hardware · IOKit verified"
        }
    }

    var checkingDescription: String {
        switch self {
        case .nativeSystem: "Hardware · macOS System API"
        case .ioKit: "Hardware · IOKit checking…"
        }
    }

    var unverifiedDescription: String {
        switch self {
        case .nativeSystem: "Hardware · macOS System API"
        case .ioKit: "Hardware · IOKit unverified"
        }
    }
}
