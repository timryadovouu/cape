import AppKit
import ApplicationServices

/// Global "double-tap ⌥ Option" shortcut: fires `onTrigger` when Option is pressed
/// twice in quick succession with no other key in between.
///
/// Receiving global key events needs Accessibility permission — without it the
/// monitors are simply never called (no crash), so the feature just stays dormant
/// until the user grants access in System Settings › Privacy › Accessibility.
final class DoubleOptionHotkey {
    var onTrigger: (() -> Void)?

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var lastOptionDown: TimeInterval = 0
    private var optionWasDown = false
    private let window: TimeInterval = 0.4        // max gap between the two taps
    private static let otherMods: NSEvent.ModifierFlags = [.command, .control, .shift]

    func start() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        // Any real keypress between the two Option taps cancels the sequence — so
        // typing e.g. ⌥e ⌥u for accented characters never fires the shortcut.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.lastOptionDown = 0
        }
    }

    func stop() {
        [flagsMonitor, keyMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        flagsMonitor = nil
        keyMonitor = nil
        optionWasDown = false
        lastOptionDown = 0
    }

    /// Ask the system for Accessibility access, showing the standard prompt if it
    /// hasn't been granted yet.
    static func requestAccessibilityPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let optionDown = flags.contains(.option)
        defer { optionWasDown = optionDown }

        // A chord with any other modifier (⌘/⌃/⇧) isn't a clean Option tap.
        if !flags.isDisjoint(with: Self.otherMods) { lastOptionDown = 0; return }
        guard optionDown, !optionWasDown else { return }   // only the press edge

        let now = event.timestamp
        if lastOptionDown != 0, now - lastOptionDown < window {
            lastOptionDown = 0
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        } else {
            lastOptionDown = now
        }
    }
}
