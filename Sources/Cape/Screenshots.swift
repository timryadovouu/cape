import AppKit
import SwiftUI

/// Dev tool: renders the README screenshots (`docs/screenshots/*.png`) from demo
/// data. Run the bare binary — its own UserDefaults domain — with a throwaway
/// data folder, so the real tasks / buffer / Screen Time are never read or touched:
///
///     CAPE_SUPPORT_DIR="$TMPDIR/cape-demo" CAPE_SCREENSHOTS=docs/screenshots .build/release/Cape
///
/// Media shows whatever Spotify / cmus is playing right now.
enum Screenshots {
    static var outputDir: URL? {
        ProcessInfo.processInfo.environment["CAPE_SCREENSHOTS"].map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Demo data

    /// Fill the (throwaway) data folder and defaults — before `AppModules` loads them.
    static func seedDemoData() {
        let fm = FileManager.default
        let dir = AppModules.supportDirectory
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.removePersistentDomain(forName: "Cape")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: day, to: today)!)!
        }
        let dayName = DateFormatter()
        dayName.dateFormat = "yyyy-MM-dd"

        // Tasks — a couple of reminders today, one tomorrow, one undated, one done.
        let todos = [
            TodoItem(title: "Prepare the keynote deck", due: at(0, 18, 0)),
            TodoItem(title: "Call the dentist", due: at(0, 15, 30)),
            TodoItem(title: "Send the invoice", due: at(1, 9, 0)),
            TodoItem(title: "Review the design specs"),
            TodoItem(title: "Book flights", done: true),
        ]
        try? JSONEncoder().encode(todos).write(to: dir.appendingPathComponent("todos.json"))

        // Buffer — a pinned link, today's copies (a picked color on top), yesterday's file.
        let buffer = dir.appendingPathComponent("localBuffer")
        func put(_ folder: String, _ name: String, _ data: Data, _ date: Date) {
            let d = buffer.appendingPathComponent(folder)
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            let url = d.appendingPathComponent(name)
            try? data.write(to: url)
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let todayFolder = dayName.string(from: today)
        let yesterdayFolder = dayName.string(from: at(-1, 0, 0))
        put("_favorites", "10-12-00-000.txt", Data("github.com/timryadovouu/cape".utf8), at(-1, 21, 10))
        put(todayFolder, "14-32-05-120.txt", Data("#FA834D".utf8), at(0, 14, 32))
        put(todayFolder, "14-05-41-310.txt", Data("milk, coffee beans, olive oil, lemons".utf8), at(0, 14, 5))
        put(todayFolder, "Gradient.png", gradientPNG(), at(0, 13, 48))
        put(yesterdayFolder, "Q3 report.pdf", Data("%PDF-1.4\n%%EOF\n".utf8), at(-1, 18, 40))

        // Screen Time — today's snapshot.
        let apps: [(String, String, Int)] = [
            ("Safari", "/Applications/Safari.app", 2760),
            ("Notes", "/System/Applications/Notes.app", 1500),
            ("Music", "/System/Applications/Music.app", 900),
            ("Terminal", "/System/Applications/Utilities/Terminal.app", 720),
            ("Messages", "/System/Applications/Messages.app", 660),
            ("Mail", "/System/Applications/Mail.app", 480),
            ("Books", "/System/Applications/Books.app", 300),
        ]
        let snapshot: [String: Any] = [
            "day": todayFolder,
            "total": apps.reduce(0) { $0 + $1.2 },
            "switches": 87,
            "apps": Dictionary(uniqueKeysWithValues: apps.map { ($0.0, $0.2) }),
            "paths": Dictionary(uniqueKeysWithValues: apps.map { ($0.0, $0.1) }),
        ]
        let screenTime = dir.appendingPathComponent("screentime")
        try? fm.createDirectory(at: screenTime, withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: snapshot)
            .write(to: screenTime.appendingPathComponent("\(todayFolder).json"))

        // Tool shortcuts, shown on the Tools tiles (⌃⌥C, ⌃⌥K).
        let mods = NSEvent.ModifierFlags([.control, .option]).rawValue
        let shortcuts = [
            Tool.colorPicker.rawValue: Shortcut(keyCode: 8, modifiers: mods, key: "C"),
            Tool.cleanKeyboard.rawValue: Shortcut(keyCode: 40, modifiers: mods, key: "K"),
        ]
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcuts), forKey: "toolShortcuts")
    }

    private static func gradientPNG() -> Data {
        let size = 96
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: NSColor(red: 0.55, green: 0.66, blue: 1, alpha: 1),
                   ending: NSColor(red: 0.78, green: 0.62, blue: 1, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: - Capture

    private static var window: NSWindow?

    /// Demo Claude sessions and dev servers — the real ones are never read.
    private static func seedDemoLive(_ modules: AppModules) {
        let now = Date()
        modules.ports.showDemo([
            .init(ports: [3000], pid: 48211, name: "node", project: "web", started: now.addingTimeInterval(-8100),
                  exposed: false, isDev: true),
            .init(ports: [8000], pid: 50112, name: "Python", project: "api", started: now.addingTimeInterval(-640),
                  exposed: true, isDev: true),
            .init(ports: [9000, 9001, 9002, 9003, 9004, 52055], pid: 50480, name: "python3.12",
                  project: "notebooks", started: now.addingTimeInterval(-4980), exposed: false, isDev: true,
                  kind: .jupyterKernel),
        ])
        // Battery use for the demo's apps (as a share of this Mac's full charge).
        let charge = EnergyMonitor.capacity ?? 200_000
        func used(_ name: String, _ pct: Double) -> EnergyMonitor.AppEnergy {
            EnergyMonitor.AppEnergy(name: name, all: charge * pct / 100, battery: charge * pct / 100,
                                    screenAll: charge * pct * 0.85 / 100, screenBattery: charge * pct * 0.85 / 100)
        }
        modules.energy.showDemo([
            "/Applications/Safari.app": used("Safari", 6.2),
            "/System/Applications/Notes.app": used("Notes", 1.1),
            "/System/Applications/Music.app": used("Music", 2.4),
            "/System/Applications/Utilities/Terminal.app": used("Terminal", 0.8),
            "/System/Applications/Messages.app": used("Messages", 0.9),
            "/System/Applications/Mail.app": used("Mail", 0.6),
            "/System/Applications/Books.app": used("Books", 0.3),
            EnergyMonitor.systemKey: used("macOS", 1.7),
        ])
        modules.settings.trackClaude = true
        // The finished one you haven't looked at yet — Clawd in its row.
        var blog = ClaudeSession(id: "demo-blog", project: "blog", status: .done, since: now.addingTimeInterval(-360),
                                 lastEvent: now, prompt: "fix the RSS feed dates", app: nil, title: "RSS feed dates")
        blog.seen = false
        modules.claude.showDemo([
            ClaudeSession(id: "demo-api", project: "api", status: .permission, since: now.addingTimeInterval(-20),
                          lastEvent: now, prompt: "add a migration for the orders table", app: nil,
                          title: "Orders migration"),
            ClaudeSession(id: "demo-cape", project: "cape", status: .working, since: now.addingTimeInterval(-134),
                          lastEvent: now, prompt: "make the sessions list drop from the notch", app: nil,
                          title: "Sessions in the notch"),
            blog,
        ], [
            ClaudePermission(id: "demo-request", sessionID: "demo-api", tool: "Bash",
                             detail: "npm run db:migrate", expires: now.addingTimeInterval(52)),
        ])
    }

    /// The collapsed brow with the Claude sessions list dropped down from it.
    private static func captureClaudePeek(_ modules: AppModules, to out: URL, name: String = "claude",
                                          open: Bool = true, then done: @escaping () -> Void) {
        let state = NotchState(settings: modules.settings)
        state.claudePeek = open
        let metrics = NotchMetrics.current()
        let peekH = ClaudePeekPanel.height(sessions: modules.claude.sessions, permissions: modules.claude.permissions)
        let size = NSSize(width: metrics.notchWidth + 2 * NotchRootView.islandWidth + (name == "claude" ? 60 : 140),
                          height: metrics.notchHeight + NotchRootView.topOvershoot + peekH + 24)
        let root = NotchRootView(state: state, pomodoro: modules.pomodoro, media: modules.media,
                                 claude: modules.claude, settings: modules.settings, todo: modules.todo,
                                 modules: modules, metrics: metrics)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.contentView = host
        w.setFrameOrigin(NSPoint(x: -20_000, y: -21_000))
        w.orderFrontRegardless()
        peekWindow = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                       pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = out.appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
            done()
        }
    }
    private static var peekWindow: NSWindow?

    /// Render each tab (and the Tools page) of the expanded panel to a PNG, then quit.
    static func capture(_ modules: AppModules) {
        guard let out = outputDir else { return }
        seedDemoLive(modules)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let state = NotchState(settings: modules.settings)
        let metrics = NotchMetrics.current()
        let size = NSSize(width: NotchRootView.panelWidth,
                          height: NotchRootView.panelHeight + NotchRootView.topOvershoot)

        let panel = ExpandedPanel(state: state, settings: modules.settings, system: modules.system,
                                  updater: modules.updater, modules: modules,
                                  notchWidth: metrics.notchWidth,
                                  topInset: metrics.notchHeight + NotchRootView.topOvershoot)
        let host = NSHostingView(rootView: ShotPanel(state: state, panel: panel))
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.contentView = host
        w.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // off every screen
        w.orderFrontRegardless()
        window = w

        let shots: [(String, () -> Void)] = [
            ("media", { state.selectModule(.media) }),
            ("timer", { state.selectModule(.timer) }),
            ("tasks", { state.selectModule(.tasks) }),
            ("buffer", { state.selectModule(.buffer) }),
            ("screenTime", { state.selectModule(.screenTime) }),
            ("tools", { state.showingTools = true }),
            ("ports", { state.showingPorts = true }),
            ("screenTimeEnergy", {
                state.showingPorts = false
                state.showingTools = false
                modules.settings.screenTimeByEnergy = true
                state.selectModule(.screenTime)
            }),
            // The welcome tour opens the panel tall.
            ("tour", {
                state.showingPorts = false
                state.tall = true
                Tour.show(0, state: state, settings: modules.settings)
            }),
            ("tourBuffer", {
                let steps = Tour.steps(modules.settings)
                Tour.show(steps.firstIndex(of: .module(.buffer)) ?? 1, state: state, settings: modules.settings)
            }),
            ("tourIslands", { Tour.show(Tour.steps(modules.settings).count - 2, state: state, settings: modules.settings) }),
            ("tourSetup", { Tour.show(Tour.steps(modules.settings).count - 1, state: state, settings: modules.settings) }),
        ]
        func shoot(_ i: Int) {
            guard i < shots.count else {
                captureClaudePeek(modules, to: out) {
                    // Then Clawd: every session done while you were away.
                    let now = Date()
                    var blog = ClaudeSession(id: "demo-blog", project: "blog", status: .done,
                                             since: now.addingTimeInterval(-1260), lastEvent: now,
                                             prompt: "fix the RSS feed dates", app: nil, title: "RSS feed dates")
                    blog.seen = false
                    var cape = ClaudeSession(id: "demo-cape", project: "cape", status: .done,
                                             since: now.addingTimeInterval(-300), lastEvent: now,
                                             prompt: "make the sessions list drop from the notch", app: nil,
                                             title: "Sessions in the notch")
                    cape.seen = false
                    var api = ClaudeSession(id: "demo-api", project: "api", status: .done,
                                            since: now.addingTimeInterval(-40), lastEvent: now,
                                            prompt: "add a migration for the orders table", app: nil,
                                            title: "Orders migration")
                    api.seen = false
                    modules.claude.showDemo([api, cape, blog], [])
                    captureClaudePeek(modules, to: out, name: "clawd", open: false) {
                        captureClaudePeek(modules, to: out, name: "clawdList") { NSApp.terminate(nil) }
                    }
                }
                return
            }
            shots[i].1()
            // The panel's height follows `tall` (the tour opens it tall).
            let size = NSSize(width: NotchRootView.panelWidth,
                              height: NotchRootView.expandedHeight(state.tall) + NotchRootView.topOvershoot)
            w.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                           pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = out.appendingPathComponent("\(shots[i].0).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
                shoot(i + 1)
            }
        }
        // Let the media poll, the cover art and the CPU/RAM readings arrive first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { shoot(0) }
    }
}

/// The expanded panel as the screenshots show it: black, rounded at the bottom,
/// as tall as the notch would open it.
private struct ShotPanel: View {
    @ObservedObject var state: NotchState
    let panel: ExpandedPanel

    var body: some View {
        panel
            .frame(width: NotchRootView.panelWidth,
                   height: NotchRootView.expandedHeight(state.tall) + NotchRootView.topOvershoot, alignment: .top)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28),
                                              style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
