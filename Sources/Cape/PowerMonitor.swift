import Foundation
import IOKit.ps

/// Watches the power source and reports the moment the charger is connected
/// (battery → AC), with the current battery level — for the notch's
/// iPhone-style charging flash. Macs without a battery never fire.
final class PowerMonitor {
    /// Called on the main thread with the battery level (0…1) when AC connects.
    var onPluggedIn: ((Double) -> Void)?

    private var source: CFRunLoopSource?
    private var onAC: Bool

    init() {
        onAC = Self.isOnAC()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // Fires on any power-source change (including every % tick); we only act
        // on the battery → AC transition.
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().changed()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
    }

    private func changed() {
        let ac = Self.isOnAC()
        defer { onAC = ac }
        guard ac, !onAC, let level = Self.batteryLevel() else { return }
        onPluggedIn?(level)
    }

    private static func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSACPowerValue
    }

    /// Internal battery charge, 0…1 — nil on a Mac without a battery.
    private static func batteryLevel() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return min(1, Double(cur) / Double(max))
        }
        return nil
    }
}
