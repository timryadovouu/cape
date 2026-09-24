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
    let updater: Updater
    lazy var settingsWindow = SettingsWindowController(settings: settings, buffer: buffer, claude: claude,
                                                       voice: voice, updater: updater)

    init() {
        let settings = Settings()
        self.settings = settings
        pomodoro = PomodoroModel(settings: settings)
        buffer = BufferManager(settings: settings)
        system = SystemStats()
        usage = AppUsageTracker(settings: settings)
        todo = TodoStore()
        media = MediaController(mediaKeys: Screenshots.outputDir == nil)
        claude = ClaudeSessionsManager(settings: settings)
        voice = VoiceDictation(settings: settings, todo: todo)
        updater = Updater(settings: settings)
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
