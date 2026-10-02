import Combine
import Foundation

/// Container for all module managers, created once and shared with the views.
final class AppModules {
    let settings: Settings
    let pomodoro: PomodoroModel
    let buffer: BufferManager
    let system: SystemStats
    let usage: AppUsageTracker
    let todo: TodoStore
    let media: MediaController
    let claude: ClaudeSessionsManager
    let voice: VoiceDictation
    let keyboardCleaner = KeyboardCleaner()
    let power = PowerMonitor()
    let ports = PortsMonitor()
    let energy: EnergyMonitor
    let updater: Updater
    let scrollReverser: ScrollReverser
    let shell: ShellIntegration
    private var subs: [AnyCancellable] = []
    lazy var settingsWindow = SettingsWindowController(settings: settings, buffer: buffer, claude: claude,
                                                       voice: voice, updater: updater, shell: shell)

    init() {
        let settings = Settings()
        self.settings = settings
        pomodoro = PomodoroModel(settings: settings)
        buffer = BufferManager(settings: settings)
        system = SystemStats()
        usage = AppUsageTracker(settings: settings)
        energy = EnergyMonitor(settings: settings, live: Screenshots.outputDir == nil)
        todo = TodoStore()
        media = MediaController(mediaKeys: Screenshots.outputDir == nil)
        claude = ClaudeSessionsManager(settings: settings, live: Screenshots.outputDir == nil)
        voice = VoiceDictation(settings: settings, todo: todo)
        updater = Updater(settings: settings)
        scrollReverser = ScrollReverser(settings: settings)
        shell = ShellIntegration(settings: settings)

        // What's switched off doesn't run at all: Screen Time (time and battery)
        // with its tab, Claude with "Track Claude Code sessions", and a turned-off
        // Pomodoro tab cancels a running timer, so its island goes too.
        subs.append(settings.$disabledModules.sink { [weak self] disabled in
            guard let self else { return }
            let screenTime = !disabled.contains(Module.screenTime.rawValue)
            usage.setActive(screenTime)
            energy.setActive(screenTime)
            if disabled.contains(Module.timer.rawValue), pomodoro.isActive { pomodoro.cancel() }
        })
        subs.append(settings.$trackClaude.sink { [weak self] on in self?.claude.setActive(on) })
    }

    /// Shared support directory: ~/Library/Application Support/Cape
    /// (`CAPE_SUPPORT_DIR` overrides it — used by the screenshot tool's demo data).
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = ProcessInfo.processInfo.environment["CAPE_SUPPORT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? base.appendingPathComponent("Cape", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
