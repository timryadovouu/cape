import SwiftUI

/// A transient message shown as the "brow widens to the left" effect.
struct NotchAlert: Equatable {
    var icon: String
    var text: String?
    var color: Color
    /// Set for the charging flash: battery level 0…1 (drawn as `ChargingBadge`).
    var battery: Double? = nil
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

    /// Shown when a Pomodoro phase changes (rest starts / next focus starts).
    func flashPhase(_ phase: PomodoroPhase) {
        let alert: NotchAlert
        switch phase {
        case .work:
            alert = NotchAlert(icon: "play.fill", text: "Focus", color: phaseColor(.work))
        case .shortBreak:
            alert = NotchAlert(icon: "cup.and.saucer.fill", text: "Break", color: phaseColor(.shortBreak))
        case .longBreak:
            alert = NotchAlert(icon: "cup.and.saucer.fill", text: "Long Break", color: phaseColor(.longBreak))
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
