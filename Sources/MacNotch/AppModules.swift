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
    lazy var settingsWindow = SettingsWindowController(settings: settings, buffer: buffer, claude: claude, voice: voice)

    init() {
        let settings = Settings()
        self.settings = settings
        pomodoro = PomodoroModel(settings: settings)
        buffer = BufferManager(settings: settings)
        system = SystemStats()
        usage = AppUsageTracker(settings: settings)
        todo = TodoStore()
        media = MediaController()
        claude = ClaudeSessionsManager(settings: settings)
        voice = VoiceDictation(settings: settings, todo: todo)
    }

    /// Shared support directory: ~/Library/Application Support/MacNotch
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
