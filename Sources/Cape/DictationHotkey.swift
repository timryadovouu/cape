import AppKit
import ApplicationServices

/// Which double-tap modifier fires dictation. `flagsChanged` reports the specific
/// physical key in `keyCode`, so the *right*-side variants can require that key.
enum VoiceHotkeyTrigger: String, CaseIterable, Identifiable {
    case option, rightOption, control
    var id: String { rawValue }

    var label: String {
        switch self {
        case .option:      return "Double-tap ⌥ Option (either side)"
        case .rightOption: return "Double-tap right ⌥ Option"
        case .control:     return "Double-tap ⌃ Control (either side)"
        }
    }

    /// The modifier this trigger watches.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option, .rightOption: return .option
        case .control:              return .control
        }
    }

    /// When set, only this physical key counts (left vs right). Virtual key code:
    /// right ⌥ = 61.
    var requiredKeyCode: UInt16? {
        switch self {
        case .rightOption: return 61
        default:           return nil
        }
    }
}

/// Global dictation keys, two independent gestures:
/// - **double-tap** the configured modifier (Option / right Option / Control) →
///   `onTrigger` (toggle recording);
/// - **hold** 🌐 Fn and/or right ⌥ Option (push-to-talk) → `onHoldStart` once the
///   key has been held past `holdDelay`, `onHoldEnd` on release. A short press
///   (Globe → emoji, a quick ⌥) never starts it, and any other key pressed while
///   holding means the modifier was used for a chord → `onHoldCancel`.
///
/// Receiving global key events needs Accessibility permission — without it the
/// monitors are simply never called (no crash), so the feature just stays dormant
/// until the user grants access in System Settings › Privacy › Accessibility.
final class DictationHotkey {
    var onTrigger: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onHoldCancel: (() -> Void)?

    /// Which gestures are on — safe to change live.
    var doubleTapEnabled = false
    var trigger: VoiceHotkeyTrigger = .option
    var holdFn = false
    var holdRightOption = false

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var localMonitor: Any?
    private var lastDown: TimeInterval = 0
    private var modWasDown = false
    private let window: TimeInterval = 0.4        // max gap between the two taps
    private static let allMods: NSEvent.ModifierFlags = [.command, .control, .shift, .option]

    // Push-to-talk
    private static let fnKey: UInt16 = 63           // 🌐 / fn
    private static let rightOptionKey: UInt16 = 61
    private let holdDelay: TimeInterval = 0.3
    private var holdKey: UInt16?                     // pressed, may become a hold
    private var holdWork: DispatchWorkItem?
    private var holding = false                      // past the delay → recording

    func start() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        // Any real keypress cancels a double-tap sequence (so typing ⌥e ⌥u never
        // fires it) and a push-to-talk hold (so Fn+⌫ or ⌥+letter isn't dictation).
        // Media keys arrive as system-defined events (subtype 8).
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] e in
            self?.handleKey(e)
        }
        // Global monitors only see events headed to *other* apps. Once Cape's own
        // panel or Settings is focused (e.g. after clicking into the notch), keys
        // come to us instead — watch those too, and pass them through untouched.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .systemDefined]) { [weak self] e in
            if e.type == .flagsChanged { self?.handleFlags(e) } else { self?.handleKey(e) }
            return e
        }
    }

    private func handleKey(_ e: NSEvent) {
        if e.type == .systemDefined, e.subtype.rawValue != 8 { return }
        lastDown = 0
        if holdKey != nil { cancelHold() }
    }

    func stop() {
        [flagsMonitor, keyMonitor, localMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        flagsMonitor = nil
        keyMonitor = nil
        localMonitor = nil
        modWasDown = false
        lastDown = 0
        cancelHold()
    }

    /// Ask the system for Accessibility access, showing the standard prompt if it
    /// hasn't been granted yet.
    static func requestAccessibilityPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        handleHold(event, flags)
        if doubleTapEnabled { handleDoubleTap(event, flags) }
    }

    // MARK: - Push-to-talk

    private func handleHold(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        let key = event.keyCode
        if let held = holdKey {
            if key == held, !Self.isDown(held, flags) { releaseHold() }   // let go
            else if key != held { cancelHold() }                          // a chord
            return
        }
        guard let candidate = holdCandidate(key, flags) else { return }
        holdKey = candidate
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.holdKey == candidate else { return }
            self.holding = true
            self.onHoldStart?()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    /// The key just pressed, if it's an enabled push-to-talk key pressed alone.
    private func holdCandidate(_ key: UInt16, _ flags: NSEvent.ModifierFlags) -> UInt16? {
        if key == Self.fnKey, holdFn, flags.contains(.function), flags.isDisjoint(with: Self.allMods) {
            return key
        }
        if key == Self.rightOptionKey, holdRightOption, flags.contains(.option),
           flags.isDisjoint(with: Self.allMods.subtracting(.option)) {
            return key
        }
        return nil
    }

    private static func isDown(_ key: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        key == fnKey ? flags.contains(.function) : flags.contains(.option)
    }

    private func releaseHold() {
        let wasHolding = holding
        resetHold()
        if wasHolding { onHoldEnd?() }
    }

    private func cancelHold() {
        let wasHolding = holding
        resetHold()
        if wasHolding { onHoldCancel?() }
    }

    private func resetHold() {
        holdWork?.cancel()
        holdWork = nil
        holdKey = nil
        holding = false
    }

    // MARK: - Double-tap

    private func handleDoubleTap(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) {
        let mod = trigger.flag
        let modDown = flags.contains(mod)
        defer { modWasDown = modDown }

        // A chord with any other modifier isn't a clean tap of our modifier.
        let others = Self.allMods.subtracting(mod)
        if !flags.isDisjoint(with: others) { lastDown = 0; return }
        guard modDown, !modWasDown else { return }   // only the press edge
        // Right-side variants: the changed key must be that physical key.
        if let kc = trigger.requiredKeyCode, event.keyCode != kc { lastDown = 0; return }

        let now = event.timestamp
        if lastDown != 0, now - lastDown < window {
            lastDown = 0
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        } else {
            lastDown = now
        }
    }
}
