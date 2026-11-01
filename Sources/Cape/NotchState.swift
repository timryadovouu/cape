import AppKit
import SwiftUI

/// A transient message shown as the "brow widens to the left" effect.
struct NotchAlert: Equatable {
    var icon: String
    var text: String?
    var color: Color
    /// Set for the charging flash: battery level 0…1 (drawn as `ChargingBadge`).
    var battery: Double? = nil
}

/// A finished terminal command, for the `cape done` strip.
struct ShellDone: Equatable {
    var ok: Bool
    var command: String
    var seconds: Int
    /// The terminal's bundle id — a click on the strip brings it to the front.
    var app: String?
    /// Each report is new, even for the same command run twice.
    var id = UUID()
}

/// UI state of the notch: expansion, the current module (remembered across
/// opens), and the transient left-side alert.
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var alert: NotchAlert?
    @Published var currentModule: Module
    /// Tasks "grow the panel vertically" toggle (reset when the notch closes).
    @Published var tall = false
    /// While the cursor hovers the collapsed timer pill: reveal the inline
    /// pomodoro controls (pause / next / cancel) without expanding the notch.
    @Published var pomodoroControls = false
    /// The Tools page is showing instead of a module (the grid button in the rail).
    @Published var showingTools = false
    /// …and on it, the Ports list.
    @Published var showingPorts = false
    /// The Claude sessions list is dropped down from the Claude island (hover).
    @Published var claudePeek = false
    /// Where Clawd looks: -1 left, 0 ahead, 1 right — toward the cursor.
    @Published var clawdLook = 0
    /// The dictation strip under the brow (no model yet → download, progress,
    /// ready), and whether it's at "ready".
    @Published var voiceNotice = false
    @Published var voiceNoticeReady = false
    /// Screenshot tool: show the strip in this phase instead of the real one.
    var voiceNoticeDemo: VoiceNoticePanel.Phase?
    /// A terminal command just finished (`cape done` / a long one): its strip
    /// under the brow, until it times out or is clicked.
    @Published var shellDone: ShellDone?
    /// The welcome tour's current step, while it's showing (keeps the notch open).
    @Published var tourStep: Int?
    /// The music island was clicked (play / pause) — don't open Media from that hover.
    var mediaIslandClicked = false

    /// Keep the notch open (ignoring the cursor) until this moment — used after
    /// a grabber tap so shrinking doesn't instantly collapse the panel.
    private(set) var holdUntil = Date.distantPast
    func holdOpen(_ seconds: TimeInterval = 2) {
        holdUntil = Date().addingTimeInterval(seconds)
    }

    private let settings: Settings
    /// If the notch was last opened more than this long ago, reset to default.
    private var recallWindow: TimeInterval { TimeInterval(settings.recallMinutes * 60) }
    private var lastOpen: Date

    private var alertWork: DispatchWorkItem?

    private let moduleKey = "lastModule"
    private let openKey = "lastOpenAt"

    init(settings: Settings) {
        self.settings = settings
        let defaults = UserDefaults.standard
        lastOpen = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: openKey))
        if let raw = defaults.string(forKey: moduleKey), let m = Module(rawValue: raw) {
            currentModule = m
        } else {
            currentModule = settings.defaultModule
        }
    }

    // MARK: - Module memory

    /// Called right before expanding: keep the last module if it was recent,
    /// otherwise fall back to the default.
    func prepareForExpand() {
        if Date().timeIntervalSince(lastOpen) > recallWindow {
            currentModule = settings.defaultModule
        }
        if !settings.isEnabled(currentModule) {
            currentModule = settings.enabledModules.first ?? .tasks
        }
        showingTools = false
        showingPorts = false
        touch()
    }

    func selectModule(_ module: Module) {
        currentModule = module
        showingTools = false
        touch()
    }

    private func touch() {
        lastOpen = Date()
        let defaults = UserDefaults.standard
        defaults.set(currentModule.rawValue, forKey: moduleKey)
        defaults.set(lastOpen.timeIntervalSinceReferenceDate, forKey: openKey)
    }

    // MARK: - Left alerts

    /// Icon-only effect shown on a new copy. Lowest priority: it never replaces a
    /// richer alert on screen (e.g. the picked color, whose hex the buffer then
    /// captures as a copy a moment later).
    func flashCopy() {
        if let a = alert, a.text != nil || a.battery != nil { return }
        show(NotchAlert(icon: "doc.on.clipboard.fill", text: nil, color: .coral), duration: 1.4)
    }

    /// Charger connected: bolt + filling battery + percent.
    func flashCharging(_ level: Double) {
        show(NotchAlert(icon: "bolt.fill", text: nil, color: .coral, battery: level), duration: 3.2)
    }

    /// A background check found a newer release.
    func flashUpdate(_ version: String) {
        show(NotchAlert(icon: "arrow.down.circle.fill", text: "Cape \(version)", color: .coral), duration: 4)
    }

    /// Eyedropper result: a swatch of the color and its hex (already copied).
    func flashColor(_ hex: String, _ color: Color) {
        show(NotchAlert(icon: "circle.fill", text: hex, color: color), duration: 2.6)
    }

    /// QR codes found in a copied image — the first one's host (+ how many more);
    /// each code is already its own buffer entry.
    func flashQR(_ payloads: [String]) {
        guard let first = payloads.first else { return }
        let more = payloads.count > 1 ? " +\(payloads.count - 1)" : ""
        show(NotchAlert(icon: "qrcode", text: QRScanner.label(first) + more, color: .coral), duration: 2.8)
    }

    /// The `cape done` strip was clicked: its terminal to the front (if it's
    /// still running), and the strip away.
    func openShellDone() {
        if let id = shellDone?.app,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) { shellDone = nil }
    }

    /// Shown when a Pomodoro phase changes (rest starts / next focus starts).
    func flashPhase(_ phase: PomodoroPhase) {
        let alert: NotchAlert
        switch phase {
        case .work:
            alert = NotchAlert(icon: "play.fill", text: String(localized: "Focus"), color: phaseColor(.work))
        case .shortBreak:
            alert = NotchAlert(icon: "cup.and.saucer.fill", text: String(localized: "Break"), color: phaseColor(.shortBreak))
        case .longBreak:
            alert = NotchAlert(icon: "cup.and.saucer.fill", text: String(localized: "Long Break"), color: phaseColor(.longBreak))
        }
        show(alert, duration: 2.8)
    }

    private func show(_ alert: NotchAlert, duration: TimeInterval) {
        alertWork?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            self.alert = alert
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                self?.alert = nil
            }
        }
        alertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
