import AppKit
import ApplicationServices
import Combine

/// "Reverse mouse wheel": flips the scroll direction of a plain mouse wheel
/// only, so the trackpad keeps macOS natural scrolling while the wheel scrolls
/// the classic way (what Scroll Reverser does — don't run both, or the wheel
/// is flipped twice).
///
/// An active CGEventTap on scroll events rewrites the deltas. The wheel is told
/// apart from the trackpad by the "continuous" flag: a notched wheel sends
/// discrete line steps, a trackpad (and a Magic Mouse) sends continuous pixel
/// deltas — those pass through untouched. Needs Accessibility, like Clean keyboard.
final class ScrollReverser {
    private let settings: Settings
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var sub: AnyCancellable?

    init(settings: Settings) {
        self.settings = settings
        sub = settings.$reverseMouseScroll.removeDuplicates().sink { [weak self] on in
            // Published fires before the stored value changes — apply on the next turn.
            DispatchQueue.main.async { self?.apply(on) }
        }
    }

    private func apply(_ on: Bool) {
        guard on else { removeTap(); return }
        guard tap == nil else { return }
        if !installTap() {
            settings.reverseMouseScroll = false
            if !AXIsProcessTrusted() {
                // The standard "grant Accessibility" prompt with a link to Settings.
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // macOS switches off a tap that stalls — switch it straight back on.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon,
                       let tap = Unmanaged<ScrollReverser>.fromOpaque(refcon).takeUnretainedValue().tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
                    ScrollReverser.flip(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon) else { return false }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = src
        return true
    }

    /// Negate every delta the event carries (lines, fixed-point and pixels), so
    /// apps reading any of them scroll the other way.
    private static func flip(_ event: CGEvent) {
        for axis in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2] {
            event.setIntegerValueField(axis, value: -event.getIntegerValueField(axis))
        }
        for axis in [CGEventField.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
                     .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2] {
            event.setDoubleValueField(axis, value: -event.getDoubleValueField(axis))
        }
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }
}
