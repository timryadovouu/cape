import AppKit
import Combine
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
    private var metrics: NotchMetrics
    private var hosting: FirstMouseHostingView<NotchRootView>!
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var shortcutsSub: AnyCancellable?

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

        let hosting = FirstMouseHostingView(rootView: makeRootView())
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hosting = hosting

        modules.buffer.onNewItem = { [weak self] _ in
            self?.state.flashCopy()
        }
        modules.buffer.onQRCodes = { [weak self] codes in self?.state.flashQR(codes) }
        modules.shell.onDone = { [weak self] done in self?.commandFinished(done) }
        modules.pomodoro.onPhaseChange = { [weak self] phase in
            self?.state.flashPhase(phase)
        }
        modules.power.onPluggedIn = { [weak self] level in
            guard let self, self.modules.settings.showCharging else { return }
            self.state.flashCharging(level)
        }
        modules.todo.onReminder = { [weak self] _ in self?.playReminderSound() }
        modules.updater.onUpdateFound = { [weak self] version in self?.state.flashUpdate(version) }
        // Global tool shortcuts — (re)registered whenever they change in Settings.
        shortcutsSub = modules.settings.$toolShortcuts.sink { [weak self] map in
            self?.registerToolShortcuts(map)
        }

        positionWindow()
        panel.orderFrontRegardless()
        startPolling()

        // Displays changed (external monitor/TV connected, arrangement or primary
        // display changed) shifts global coordinates and can strand the brow on the
        // wrong screen — re-anchor to the built-in notch screen whenever that happens.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.screensChanged() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func makeRootView() -> NotchRootView {
        NotchRootView(state: state, pomodoro: modules.pomodoro,
                      media: modules.media, claude: modules.claude,
                      settings: modules.settings, todo: modules.todo,
                      modules: modules, metrics: metrics)
    }

    private func screensChanged() {
        metrics = .current()               // re-find the built-in notch screen
        hosting.rootView = makeRootView()  // pick up the new notch size, if any
        positionWindow()                   // re-anchor to that screen's current coords
    }

    private func positionWindow() {
        let f = metrics.screenFrame
        let x = metrics.centerX - windowWidth / 2
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
        return NSRect(x: metrics.centerX - w / 2, y: bottom, width: w, height: f.maxY - bottom + 40)
    }

    /// Expanded panel zone (with margin), in screen coordinates.
    private var expandedZone: NSRect {
        let f = metrics.screenFrame
        let pad: CGFloat = 12
        let w = NotchRootView.panelWidth + pad * 2
        let bottom = f.maxY - NotchRootView.expandedHeight(state.tall) - pad
        return NSRect(x: metrics.centerX - w / 2, y: bottom, width: w, height: f.maxY - bottom + 40)
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
        // Hovering the Claude island drops the sessions list down from it; it stays
        // while the cursor is over the island or the list.
        if state.claudePeek {
            // Sliding left from the Claude island along the brow, over the camera,
            // opens the full panel — the list itself hangs below the brow.
            let f = metrics.screenFrame
            if mouse.y > f.maxY - metrics.notchHeight + 2,
               mouse.x < metrics.centerX + metrics.notchWidth / 2,
               mouse.x > metrics.centerX - metrics.notchWidth / 2 {
                state.claudePeek = false
                expand()
                return
            }
            if let zone = claudePeekZone(), zone.contains(mouse) {
                panel.ignoresMouseEvents = false
                return
            }
            state.claudePeek = false
        }
        if let zone = claudeIslandZone(), zone.contains(mouse) {
            state.claudePeek = true
            panel.ignoresMouseEvents = false
            return
        }
        // The music island (left of the camera): a click toggles play / pause
        // (handled by the view); resting on it a moment opens Media — unless it
        // was just clicked. A ringing reminder (far right) opens Tasks and silences it.
        if let zone = mediaIslandZone(), zone.contains(mouse) {
            panel.ignoresMouseEvents = false
            let since = mediaHoverStart ?? Date()
            mediaHoverStart = since
            if modules.settings.openMediaOnHover, !state.mediaIslandClicked,
               Date().timeIntervalSince(since) > 0.45 {
                expand(to: .media)
            }
            return
        }
        mediaHoverStart = nil
        state.mediaIslandClicked = false
        if let zone = reminderZone(), zone.contains(mouse) {
            modules.todo.dismissRinging()
            expand(to: .tasks)
        } else if notchZone.contains(mouse) {
            expand()
        } else {
            panel.ignoresMouseEvents = true
        }
    }

    /// When the cursor came onto the music island (for the open-Media delay).
    private var mediaHoverStart: Date?

    private var claudeIslandShown: Bool {
        let c = modules.claude
        return modules.settings.trackClaude && (c.anyWorking || c.needsYou) && !c.sessions.isEmpty
    }

    /// The small Claude island just right of the camera.
    private func claudeIslandZone() -> NSRect? {
        guard claudeIslandShown else { return nil }
        let f = metrics.screenFrame
        let startX = metrics.centerX + metrics.notchWidth / 2
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: startX, y: bottom, width: NotchRootView.claudeIslandWidth, height: f.maxY - bottom + 40)
    }

    /// The island plus the list under it (same geometry as NotchRootView).
    private func claudePeekZone() -> NSRect? {
        guard claudeIslandShown else { return nil }
        let f = metrics.screenFrame
        let c = modules.claude
        let right = metrics.centerX + metrics.notchWidth / 2 + NotchRootView.claudeIslandWidth
        let left = mediaLeftEdge()
        let h = ClaudePeekPanel.height(sessions: c.sessions, permissions: c.permissions)
        let bottom = f.maxY - metrics.notchHeight - NotchRootView.topOvershoot - h - 10
        return NSRect(x: left - 10, y: bottom, width: right - left + 20, height: f.maxY - bottom + 40)
    }

    /// Left end of the collapsed brow (the music island / alert, if any).
    private func mediaLeftEdge() -> CGFloat {
        let notchLeft = metrics.centerX - metrics.notchWidth / 2
        let m = modules.media
        let hasIsland = (m.source != .none || m.isPlaying) && modules.settings.isEnabled(.media)
        if let alert = state.alert { return notchLeft - NotchRootView.alertWidth(alert) }
        // No left island: the open list gets an empty one, mirroring Claude's.
        return notchLeft - (hasIsland || state.claudePeek ? NotchRootView.islandWidth : 0)
    }

    /// Screen rect of the collapsed timer pill (grown to include the controls
    /// while shown). The notch stays centered on the camera, so the right
    /// extension always starts at the notch's right edge + the Claude island.
    private func pomodoroControlZone() -> NSRect? {
        guard modules.pomodoro.isActive else { return nil }
        let f = metrics.screenFrame
        let claudeExt: CGFloat = claudeIslandShown ? NotchRootView.claudeIslandWidth : 0
        let rightTotal = NotchRootView.timerPillWidth
            + (state.pomodoroControls ? NotchRootView.pomodoroControlsWidth : 0)
        let startX = metrics.centerX + metrics.notchWidth / 2 + claudeExt
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: startX - 6, y: bottom,
                      width: rightTotal + 12, height: f.maxY - bottom + 40)
    }

    /// Screen rect of the collapsed music island (equalizer while playing, pause
    /// glyph while paused) — nil when the feature is off in Settings, or the island
    /// isn't shown: no player, an alert is borrowing the left side, or the Media
    /// module is turned off.
    private func mediaIslandZone() -> NSRect? {
        let media = modules.media
        guard media.source != .none || media.isPlaying,
              state.alert == nil,
              modules.settings.isEnabled(.media) else { return nil }
        let f = metrics.screenFrame
        let endX = metrics.centerX - metrics.notchWidth / 2
        let w = NotchRootView.mediaIslandWidth
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: endX - w - 6, y: bottom,
                      width: w + 6, height: f.maxY - bottom + 40)
    }

    /// Screen rect of the ringing-reminder pill — outermost on the right, after
    /// the Claude island and the timer pill (with its controls, if revealed).
    private func reminderZone() -> NSRect? {
        let ringing = modules.todo.ringing
        guard !ringing.isEmpty else { return nil }
        let f = metrics.screenFrame
        let claudeExt: CGFloat = claudeIslandShown ? NotchRootView.claudeIslandWidth : 0
        let timerExt: CGFloat = modules.pomodoro.isActive
            ? NotchRootView.timerPillWidth
                + (state.pomodoroControls ? NotchRootView.pomodoroControlsWidth : 0)
            : 0
        let startX = metrics.centerX + metrics.notchWidth / 2 + claudeExt + timerExt
        let w = NotchRootView.reminderWidth(NotchRootView.reminderText(ringing))
        let bottom = f.maxY - metrics.notchHeight - 2
        return NSRect(x: startX, y: bottom, width: w + 6, height: f.maxY - bottom + 40)
    }

    private func registerToolShortcuts(_ map: [String: Shortcut]) {
        for tool in Tool.allCases {
            if let shortcut = map[tool.rawValue] {
                GlobalHotkeys.shared.register(id: tool.hotkeyID, shortcut) { [weak self] in
                    guard let self else { return }
                    self.modules.run(tool, state: self.state)
                }
            } else {
                GlobalHotkeys.shared.unregister(id: tool.hotkeyID)
            }
        }
    }

    /// `cape done` always flashes; a long command only while its terminal isn't in front.
    private func commandFinished(_ done: ShellIntegration.Done) {
        if done.auto, let app = done.app,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app { return }
        state.flashDone(ok: done.ok, command: done.command, seconds: done.seconds)
        if modules.settings.shellSound {
            let sound = NSSound(named: done.ok ? "Glass" : "Basso")
            doneChime = sound
            sound?.stop()
            sound?.play()
        }
    }
    private var doneChime: NSSound?

    private var reminderChime: NSSound?
    private func playReminderSound() {
        let s = modules.settings
        guard s.reminderSound else { return }
        let sound = NSSound(named: s.reminderSoundName) ?? NSSound(named: "Ping")
        reminderChime = sound
        sound?.stop()
        sound?.play()
    }

    /// Open the panel — on `module` if given, else on the remembered one.
    private func expand(to module: Module? = nil) {
        guard !state.expanded else { return }
        state.claudePeek = false
        panel.ignoresMouseEvents = false
        state.prepareForExpand()   // restore last module (or reset after 30 min)
        if let module { state.selectModule(module) }
        state.expanded = true
        // Note: we do NOT make the panel key on hover, so focus doesn't jump away
        // from whatever the user is typing in. `becomesKeyOnlyIfNeeded` lets the
        // Tasks text field take focus only when it's actually clicked.
    }

    private func collapse() {
        guard state.expanded else { return }
        state.claudePeek = false
        state.expanded = false
        state.tall = false          // reset the Tasks grow-toggle on close
        panel.ignoresMouseEvents = true
    }
}
