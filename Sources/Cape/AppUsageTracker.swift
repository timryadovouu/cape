import AppKit

struct AppUsage: Identifiable, Hashable {
    let id: String       // app name
    var name: String { id }
    let seconds: Int
    let iconPath: String?    // app bundle path, for its icon
}

/// One day's screen-time snapshot.
struct DayStats {
    let date: Date
    let total: Int
    let switches: Int
    let apps: [AppUsage]
    static func empty(_ date: Date) -> DayStats {
        DayStats(date: date, total: 0, switches: 0, apps: [])
    }
}

/// Screen-time tracking done locally: every second we credit the frontmost app.
/// Each day is stored as its own JSON snapshot so history is kept and browsable.
/// Everything stays on this Mac. Files older than the retention setting are pruned.
final class AppUsageTracker: ObservableObject {
    @Published private(set) var ranked: [AppUsage] = []
    @Published private(set) var totalSeconds = 0
    @Published private(set) var switchCount = 0

    private let settings: Settings
    private var perApp: [String: Int] = [:]
    private var paths: [String: String] = [:]   // app name -> bundle path
    private var lastApp: String?
    private var day = AppUsageTracker.dayString(Date())
    private var tick = 0
    private var timer: Timer?

    private let selfName = NSRunningApplication.current.localizedName ?? "Cape"

    /// Don't credit time while the screen is locked / at the login window /
    /// running the screensaver — that isn't real usage.
    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
    ]

    init(settings: Settings) {
        self.settings = settings
        migrateLegacy()
        loadToday()
        cleanupOld()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Tracking

    private func step() {
        let today = Self.dayString(Date())
        if today != day {
            save()               // finalize the day that just ended
            cleanupOld()
            perApp = [:]; paths = [:]; totalSeconds = 0; switchCount = 0; lastApp = nil
            day = today
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let app = front.localizedName,
              app != selfName,
              !Self.ignoredBundleIDs.contains(front.bundleIdentifier ?? "") else { rebuild(); return }

        if app != lastApp {
            if lastApp != nil { switchCount += 1 }
            lastApp = app
        }
        perApp[app, default: 0] += 1
        if let path = front.bundleURL?.path { paths[app] = path }
        totalSeconds += 1

        tick += 1
        if tick % 15 == 0 { save() }
        rebuild()
    }

    private func rebuild() {
        ranked = perApp
            .map { AppUsage(id: $0.key, seconds: $0.value, iconPath: paths[$0.key]) }
            .sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Browsing days

    /// `offset` 0 = today, -1 = yesterday, …
    var today: DayStats {
        DayStats(date: Calendar.current.startOfDay(for: Date()),
                 total: totalSeconds, switches: switchCount, apps: ranked)
    }

    func loadDay(offset: Int) -> DayStats {
        let d = dateFor(offset)
        guard let data = try? Data(contentsOf: fileURL(Self.dayString(d))),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .empty(d)
        }
        let apps = snap.apps
            .map { AppUsage(id: $0.key, seconds: $0.value, iconPath: snap.paths?[$0.key]) }
            .sorted { $0.seconds > $1.seconds }
        return DayStats(date: d, total: snap.total, switches: snap.switches, apps: apps)
    }

    /// Most negative offset that still has stored data (0 if only today exists).
    func earliestOffset() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var earliest = 0
        for f in files where f.hasSuffix(".json") {
            guard let d = Self.date(from: String(f.dropLast(5))) else { continue }
            let diff = Calendar.current.dateComponents([.day],
                from: today, to: Calendar.current.startOfDay(for: d)).day ?? 0
            earliest = min(earliest, diff)
        }
        return earliest
    }

    private func dateFor(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var day: String
        var total: Int
        var switches: Int
        var apps: [String: Int]
        var paths: [String: String]?
    }

    private var dir: URL {
        let u = AppModules.supportDirectory.appendingPathComponent("screentime", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func fileURL(_ dayStr: String) -> URL { dir.appendingPathComponent("\(dayStr).json") }

    private func save() {
        let snap = Snapshot(day: day, total: totalSeconds, switches: switchCount,
                            apps: perApp, paths: paths)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: fileURL(day)) }
    }

    private func loadToday() {
        guard let data = try? Data(contentsOf: fileURL(day)),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        perApp = snap.apps
        paths = snap.paths ?? [:]
        totalSeconds = snap.total
        switchCount = snap.switches
        rebuild()
    }

    private func cleanupOld() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.screenTimeRetentionDays,
                                           to: Calendar.current.startOfDay(for: Date()))!
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files where f.hasSuffix(".json") {
            let name = String(f.dropLast(5))
            if let d = Self.date(from: name), Calendar.current.startOfDay(for: d) < cutoff {
                try? FileManager.default.removeItem(at: fileURL(name))
            }
        }
    }

    /// Move the old single-file store into the per-day folder, once.
    private func migrateLegacy() {
        let legacy = AppModules.supportDirectory.appendingPathComponent("screentime.json")
        guard FileManager.default.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let dest = fileURL(snap.day)
        if !FileManager.default.fileExists(atPath: dest.path) { try? data.write(to: dest) }
        try? FileManager.default.removeItem(at: legacy)
    }

    // MARK: - Date helpers

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func dayString(_ d: Date) -> String { fmt.string(from: d) }
    static func date(from s: String) -> Date? { fmt.date(from: s) }
}

/// "1h 23m" / "12m" / "45s"
func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}
