import AppKit
import SwiftUI

/// A panel that can become the key window without activating the whole app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// NSHostingView that accepts the first mouse click, so buttons in the expanded
/// panel work on the first click without focusing the window first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }
}

/// Owns the brow window: positions it over the notch and expands/collapses it
/// based on the cursor position (hover over the notch).
final class NotchController {
    private let panel: NotchPanel
    private let state: NotchState
    private let modules: AppModules
    private let metrics: NotchMetrics
    private var pollTimer: Timer?

    private let windowWidth: CGFloat = 640
    // Tall enough to hold the expanded panel in its "tall" (Tasks-grown) size.
    private let windowHeight: CGFloat = 480

    init(modules: AppModules) {
        self.modules = modules
        self.metrics = .current()
        self.state = NotchState(settings: modules.settings)

        panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root = NotchRootView(state: state, pomodoro: modules.pomodoro,
                                 media: modules.media, claude: modules.claude,
                                 settings: modules.settings, modules: modules, metrics: metrics)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        modules.buffer.onNewItem = { [weak self] _ in
            self?.state.flashCopy()
        }
        modules.pomodoro.onPhaseChange = { [weak self] phase in
            self?.state.flashPhase(phase)
        }

        positionWindow()
        panel.orderFrontRegardless()
        startPolling()
    }

    private func positionWindow() {
        let f = metrics.screenFrame
        let x = f.midX - windowWidth / 2
        // Push the top a few points above the screen edge so the black fully
        // covers the very top rows (no thin menu-bar line showing through).
        let y = f.maxY - windowHeight + NotchRootView.topOvershoot
        panel.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    // MARK: - Hover tracking

    private func startPolling() {
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    /// Notch trigger zone (slightly enlarged), in screen coordinates.
    /// The zone extends above the screen's top edge so that pressing the cursor
    /// right to the top (y == screen max, which `NSRect.contains` treats as the
    /// exclusive upper bound) still counts as hovering the notch.
    private var notchZone: NSRect {
        let f = metrics.screenFrame
        let w = metrics.notchWidth + 24
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: f.midX - w / 2, y: bottom, width: w, height: f.maxY - bottom + 40)
    }

    /// Expanded panel zone (with margin), in screen coordinates.
    private var expandedZone: NSRect {
        let f = metrics.screenFrame
        let pad: CGFloat = 12
        let w = NotchRootView.panelWidth + pad * 2
        let bottom = f.maxY - NotchRootView.expandedHeight(state.tall) - pad
        return NSRect(x: f.midX - w / 2, y: bottom, width: w, height: f.maxY - bottom + 40)
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        if state.expanded {
            if Date() < state.holdUntil { return }    // grace period after a grabber tap
            if !expandedZone.contains(mouse) { collapse() }
            return
        }
        // Collapsed: hovering the running timer pill reveals its inline controls
        // (pause / next / cancel) and makes them clickable — without expanding.
        if let zone = pomodoroControlZone(), zone.contains(mouse) {
            if !state.pomodoroControls { state.pomodoroControls = true }
            panel.ignoresMouseEvents = false
            return
        }
        if state.pomodoroControls { state.pomodoroControls = false }
        if notchZone.contains(mouse) {
            expand()
        } else {
            panel.ignoresMouseEvents = true
        }
    }

    /// Screen rect of the collapsed timer pill (grown to include the controls
    /// while shown). The notch stays centered on the camera, so the right
    /// extension always starts at the notch's right edge + the Claude island.
    private func pomodoroControlZone() -> NSRect? {
        guard modules.pomodoro.isActive else { return nil }
        let f = metrics.screenFrame
        let claudeExt: CGFloat =
            (modules.settings.trackClaude && modules.claude.anyWorking) ? 20 : 0
        let rightTotal = NotchRootView.timerPillWidth
            + (state.pomodoroControls ? NotchRootView.pomodoroControlsWidth : 0)
        let startX = f.midX + metrics.notchWidth / 2 + claudeExt
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: startX - 6, y: bottom,
                      width: rightTotal + 12, height: f.maxY - bottom + 40)
    }

    private func expand() {
        guard !state.expanded else { return }
        panel.ignoresMouseEvents = false
        state.prepareForExpand()   // restore last module (or reset after 30 min)
        state.expanded = true
        // Note: we do NOT make the panel key on hover, so focus doesn't jump away
        // from whatever the user is typing in. `becomesKeyOnlyIfNeeded` lets the
        // Tasks text field take focus only when it's actually clicked.
    }

    private func collapse() {
        guard state.expanded else { return }
        state.expanded = false
        state.tall = false          // reset the Tasks grow-toggle on close
        panel.ignoresMouseEvents = true
    }
}
