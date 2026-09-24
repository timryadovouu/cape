import AppKit
import ApplicationServices
import SwiftUI

/// "Clean keyboard" mode: swallows every key press system-wide (an active
/// CGEventTap) and covers every screen with an overlay, so the keyboard can be
/// wiped without typing anything. The trackpad / mouse stay live — the overlay's
/// Done button is the way out — with a safety auto-unlock, and it also unlocks
/// on sleep or screen lock.
///
/// An active event tap needs Accessibility permission. Without it the tap can't
/// be created and the mode refuses to start, so it never shows a "locked" screen
/// while keys still get through.
final class KeyboardCleaner: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remaining = 0    // seconds until auto-unlock

    static let duration = 120

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard !isActive else { return }
        guard installTap() else {
            if AXIsProcessTrusted() {
                let alert = NSAlert()
                alert.messageText = "Couldn't lock the keyboard"
                alert.informativeText = "macOS refused the keyboard event tap. Try again in a moment."
                alert.runModal()
            } else {
                // Shows the standard "grant Accessibility" prompt with a link to Settings.
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
            return
        }
        isActive = true
        remaining = Self.duration
        showOverlays()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Never leave the keyboard dead across sleep or a locked screen.
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.willSleepNotification,
                                             object: nil, queue: .main) { [weak self] _ in self?.stop() }))
        let dnc = DistributedNotificationCenter.default()
        observers.append((dnc, dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                               object: nil, queue: .main) { [weak self] _ in self?.stop() }))
    }

    func stop() {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        removeTap()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        isActive = false
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { stop() }
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        mask |= CGEventMask(1) << 14   // NX_SYSDEFINED — volume / brightness / media keys

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // macOS switches off a tap that stalls — switch it straight back on.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon,
                       let tap = Unmanaged<KeyboardCleaner>.fromOpaque(refcon).takeUnretainedValue().tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                // System-defined events also carry mouse-button state; only swallow
                // the special-key ones (subtype 8 = aux control buttons).
                if type.rawValue == 14, NSEvent(cgEvent: event)?.subtype.rawValue != 8 {
                    return Unmanaged.passUnretained(event)
                }
                return nil   // swallow the key
            },
            userInfo: refcon) else { return false }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = src
        return true
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

    // MARK: - Overlay

    private func showOverlays() {
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            let host = FirstMouseHostingView(rootView: KeyboardCleanerOverlay(cleaner: self))
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.orderFrontRegardless()
            windows.append(panel)
        }
    }
}

/// Full-screen "keyboard locked" card with the way out.
struct KeyboardCleanerOverlay: View {
    @ObservedObject var cleaner: KeyboardCleaner

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 16) {
                Image(systemName: "keyboard")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.coral)
                Text("Keyboard locked for cleaning")
                    .font(.system(size: 26, weight: .semibold))
                Text("Wipe away — key presses are ignored. The trackpad still works.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                Button { cleaner.stop() } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 160, height: 40)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                Text("Unlocks automatically in \(formatTime(TimeInterval(cleaner.remaining)))")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
