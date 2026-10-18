import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics

private typealias DisplayServicesCanChangeFunction = @convention(c) (CGDirectDisplayID) -> Bool
private typealias DisplayServicesGetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DisplayServicesSetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias CoreDisplayGetFunction = @convention(c) (CGDirectDisplayID) -> Double
private typealias CoreDisplaySetFunction = @convention(c) (CGDirectDisplayID, Double) -> Void

enum HardwareBrightnessMethod {
    case nativeSystem
    case ioKit
}

enum HardwareBrightnessWriteResult {
    case verified(HardwareBrightnessMethod)
    case accepted(HardwareBrightnessMethod)
    case failed

    var method: HardwareBrightnessMethod? {
        switch self {
        case let .verified(method), let .accepted(method): method
        case .failed: nil
        }
    }
}

/// Hardware brightness used by macOS itself. DisplayServices is tried first,
/// with CoreDisplay as a compatibility fallback. Both are loaded dynamically
/// so a missing symbol degrades safely to the public IOKit/software paths.
@MainActor
private final class NativeDisplayBrightnessAPI {
    static let shared = NativeDisplayBrightnessAPI()

    private let displayServicesHandle: UnsafeMutableRawPointer?
    private let coreDisplayHandle: UnsafeMutableRawPointer?
    private let canChange: DisplayServicesCanChangeFunction?
    private let getBrightness: DisplayServicesGetFunction?
    private let setBrightness: DisplayServicesSetFunction?
    private let coreGetBrightness: CoreDisplayGetFunction?
    private let coreSetBrightness: CoreDisplaySetFunction?

    private init() {
        let displayServicesHandle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY | RTLD_LOCAL
        )
        self.displayServicesHandle = displayServicesHandle
        if let displayServicesHandle {
            canChange = dlsym(displayServicesHandle, "DisplayServicesCanChangeBrightness").map {
                unsafeBitCast($0, to: DisplayServicesCanChangeFunction.self)
            }
            getBrightness = dlsym(displayServicesHandle, "DisplayServicesGetBrightness").map {
                unsafeBitCast($0, to: DisplayServicesGetFunction.self)
            }
            setBrightness = dlsym(displayServicesHandle, "DisplayServicesSetBrightness").map {
                unsafeBitCast($0, to: DisplayServicesSetFunction.self)
            }
        } else {
            canChange = nil
            getBrightness = nil
            setBrightness = nil
        }

        let coreDisplayHandle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY | RTLD_LOCAL
        )
        self.coreDisplayHandle = coreDisplayHandle
        if let coreDisplayHandle {
            coreGetBrightness = dlsym(coreDisplayHandle, "CoreDisplay_Display_GetUserBrightness").map {
                unsafeBitCast($0, to: CoreDisplayGetFunction.self)
            }
            coreSetBrightness = dlsym(coreDisplayHandle, "CoreDisplay_Display_SetUserBrightness").map {
                unsafeBitCast($0, to: CoreDisplaySetFunction.self)
            }
        } else {
            coreGetBrightness = nil
            coreSetBrightness = nil
        }
    }

    deinit {
        if let displayServicesHandle { dlclose(displayServicesHandle) }
        if let coreDisplayHandle { dlclose(coreDisplayHandle) }
    }

    func read(displayID: CGDirectDisplayID) -> Double? {
        guard CGDisplayIsBuiltin(displayID) != 0 else { return nil }
        if let getBrightness {
            var value: Float = 0
            if getBrightness(displayID, &value) == 0, value.isFinite, value >= 0, value <= 1.5 {
                return AdaptiveMath.clamp(Double(value))
            }
        }

        if let coreGetBrightness {
            let value = coreGetBrightness(displayID)
            if value.isFinite, value >= 0, value <= 1.5 {
                return AdaptiveMath.clamp(value)
            }
        }
        return nil
    }

    func set(_ brightness: Double, displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) != 0 else { return false }
        let value = AdaptiveMath.clamp(brightness)
        if let canChange, let setBrightness, let getBrightness, canChange(displayID) {
            guard setBrightness(displayID, Float(value)) == 0 else { return false }
            var applied: Float = 0
            return getBrightness(displayID, &applied) == 0 && abs(Double(applied) - value) <= 0.02
        }

        if let coreGetBrightness, let coreSetBrightness {
            let current = coreGetBrightness(displayID)
            guard current.isFinite, current >= 0, current <= 1.5 else { return false }
            coreSetBrightness(displayID, value)
            let applied = coreGetBrightness(displayID)
            return applied.isFinite && abs(applied - value) <= 0.02
        }
        return false
    }
}

/// Hardware brightness control with macOS native APIs first and public IOKit
/// as a compatibility fallback. Virtual/DisplayLink outputs may expose neither.
@MainActor
struct SystemDisplayBrightnessController {
    private let native = NativeDisplayBrightnessAPI.shared
    private let serviceClasses = [
        "AppleBacklightDisplay",
        "AppleDisplay",
        "IODisplayConnect",
    ]

    func read(displayID: CGDirectDisplayID) -> Double? {
        if let brightness = native.read(displayID: displayID) {
            return brightness
        }
        if CGDisplayIsBuiltin(displayID) != 0, let brightness = readAppleSiliconBacklight() {
            return brightness
        }

        var brightness: Double?
        _ = visitMatchingServices(displayID: displayID) { service in
            var value: Float = 0
            guard
                IODisplayGetFloatParameter(
                    service,
                    0,
                    kIODisplayBrightnessKey as CFString,
                    &value
                ) == kIOReturnSuccess, value.isFinite, value >= 0, value <= 1.5
            else {
                return false
            }
            brightness = AdaptiveMath.clamp(Double(value))
            return true
        }
        return brightness
    }

    func setBrightness(_ brightness: Double, displayID: CGDirectDisplayID) -> HardwareBrightnessWriteResult {
        if native.set(brightness, displayID: displayID) {
            return .verified(.nativeSystem)
        }
        let value = Float(AdaptiveMath.clamp(brightness))
        var result = HardwareBrightnessWriteResult.failed
        _ = visitMatchingServices(displayID: displayID) { service in
            guard
                IODisplaySetFloatParameter(
                    service,
                    0,
                    kIODisplayBrightnessKey as CFString,
                    value
                ) == kIOReturnSuccess
            else { return false }

            var observed: Float = 0
            let observedBrightness: Double? =
                IODisplayGetFloatParameter(
                    service,
                    0,
                    kIODisplayBrightnessKey as CFString,
                    &observed
                ) == kIOReturnSuccess
                ? Double(observed) : nil
            result =
                AdaptiveMath.verifyBrightness(
                    requested: brightness,
                    observed: observedBrightness
                ) == .matches ? .verified(.ioKit) : .accepted(.ioKit)
            return true
        }
        return result
    }

    private func visitMatchingServices(
        displayID: CGDirectDisplayID,
        _ body: (io_service_t) -> Bool
    ) -> Bool {
        for className in serviceClasses {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(className),
                IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess
            else { continue }
            defer { IOObjectRelease(iterator) }

            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                let matches = serviceMatches(service, className: className, displayID: displayID)
                let succeeded = matches && body(service)
                IOObjectRelease(service)
                if succeeded { return true }
            }
        }
        return false
    }

    private func serviceMatches(
        _ service: io_service_t,
        className: String,
        displayID: CGDirectDisplayID
    ) -> Bool {
        if let unmanagedInfo = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)) {
            let info = unmanagedInfo.takeRetainedValue() as NSDictionary
            let vendor = (info["DisplayVendorID"] as? NSNumber)?.uint32Value
            let product = (info["DisplayProductID"] as? NSNumber)?.uint32Value
            let serial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            let displaySerial = CGDisplaySerialNumber(displayID)

            if vendor == CGDisplayVendorNumber(displayID), product == CGDisplayModelNumber(displayID) {
                return serial == 0 || displaySerial == 0 || serial == displaySerial
            }
        }

        return CGDisplayIsBuiltin(displayID) != 0
            && className == "AppleBacklightDisplay"
    }

    /// Apple Silicon publishes its built-in panel as AppleARMBacklight instead
    /// of the legacy IODisplay service expected by IODisplaySetFloatParameter.
    /// IORegistryEntryCreateCFProperty can read its current normalized value,
    /// but AppleARMBacklight does not publicly expose a supported setter.
    private func readAppleSiliconBacklight() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleARMBacklight")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let range = appleSiliconBrightnessRange(service: service), range.maximum > range.minimum else {
            return nil
        }
        return AdaptiveMath.clamp(
            Double(range.value - range.minimum) / Double(range.maximum - range.minimum)
        )
    }

    private func appleSiliconBrightnessRange(
        service: io_service_t
    ) -> (value: Int32, minimum: Int32, maximum: Int32)? {
        guard
            let property = IORegistryEntryCreateCFProperty(
                service,
                kIODisplayParametersKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
            let parameters = property as? NSDictionary,
            let brightness = parameters[kIODisplayBrightnessKey] as? NSDictionary,
            let value = (brightness[kIODisplayValueKey] as? NSNumber)?.int32Value,
            let minimum = (brightness[kIODisplayMinValueKey] as? NSNumber)?.int32Value,
            let maximum = (brightness[kIODisplayMaxValueKey] as? NSNumber)?.int32Value
        else { return nil }

        return (value, minimum, maximum)
    }
}

struct AmbientLightReader {
    private let serviceNames = [
        "AppleLMUController",
        "AppleHIDALSService",
        "AppleSPUALSSealionDriver",
        "AppleSPUALSSunfishDriver",
        "AppleSPUVD6287",
        "AppleTCS3490",
    ]
    private let propertyNames = ["CurrentLux", "Lux", "lux", "Illuminance", "illuminance"]

    func read() -> Double? {
        if let override = ProcessInfo.processInfo.environment["NUNI_LUX"],
            let value = Double(override), value >= 0
        {
            return value
        }

        for serviceName in serviceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }

            for propertyName in propertyNames {
                guard
                    let value = IORegistryEntryCreateCFProperty(
                        service,
                        propertyName as CFString,
                        kCFAllocatorDefault,
                        0
                    )?.takeRetainedValue()
                else { continue }

                if let number = value as? NSNumber {
                    let lux = number.doubleValue
                    if lux.isFinite, lux >= 0 { return lux }
                }
            }
        }
        return nil
    }
}
