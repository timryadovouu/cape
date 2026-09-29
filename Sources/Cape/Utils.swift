import SwiftUI
import AppKit

extension Color {
    /// The app's coral accent (#FA834D) — used for Claude, the copy flash, etc.
    static let coral = Color(red: 0.980, green: 0.514, blue: 0.302)
    /// The one red: focus time, Quit, CPU, delete / stop.
    static let capeRed = Color(red: 1.0, green: 0.35, blue: 0.35)
}

/// The interface language — English (the default) or Russian, set in
/// Settings › General. macOS reads an app's language once, at launch, so
/// `applyAtLaunch()` runs first thing and a change needs a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ru
    var id: String { rawValue }

    /// Each in its own language, so it's findable whatever the current one is.
    var label: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    static let key = "appLanguage"

    /// The saved choice (anything else, like an old "system", reads as English).
    static var saved: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .en
    }

    /// Point macOS's per-app language list at the saved choice — called before
    /// anything is localized, so it holds for this launch whatever the system
    /// language is.
    static func applyAtLaunch() {
        UserDefaults.standard.set([saved.rawValue], forKey: "AppleLanguages")
        launched = saved
    }

    /// The choice this launch runs in (a different one needs a relaunch).
    static private(set) var launched: AppLanguage = .en

    /// The language the interface is actually in right now.
    static var running: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// For dates and weekdays — formatters follow the system's region, not the
    /// app's language, so they get it spelled out.
    static var locale: Locale { Locale(identifier: running) }

    /// Relaunch Cape (after a language change): wait for this process to exit,
    /// then open the app again.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                        Bundle.main.bundlePath]
        try? sh.run()
        NSApp.terminate(nil)
    }
}

/// A small coral on/off switch for the dark notch (the system switch looks
/// washed out there).
struct CoralSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.coral : .white.opacity(0.18))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// System sounds that `NSSound(named:)` can actually play, gathered from the
/// standard Sounds directories. Note: macOS Sequoia's redesigned alert sounds
/// (Boop, Breeze, Funky, …) live in a private system store and are not reachable
/// by third-party apps, so only the classic set (Basso … Tink) shows up here.
enum SystemSounds {
    static let available: [String] = {
        let dirs = ["/System/Library/Sounds",
                    "/Library/Sounds",
                    (NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds")]
        let exts: Set<String> = ["aiff", "aif", "caf", "wav", "m4a"]
        var names = Set<String>()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for f in files where exts.contains((f as NSString).pathExtension.lowercased()) {
                names.insert((f as NSString).deletingPathExtension)
            }
        }
        return names.sorted()
    }()

    /// Preview a sound, cutting off any preview still playing (so hovering down
    /// the list doesn't stack sounds on top of each other).
    private static var preloaded: NSSound?
    static func preview(_ name: String) {
        preloaded?.stop()
        let s = NSSound(named: name)
        preloaded = s
        s?.play()
    }
}

/// Best-effort check for whether a Focus / Do Not Disturb is currently active.
///
/// There is no public API for this, so we read the Focus state file macOS keeps
/// in the user's Library. It reliably catches a manually-toggled Focus; if the
/// file is missing or unreadable we assume Focus is off (so the sound plays).
enum FocusMonitor {
    static var isActive: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return false }
        return entries.contains { entry in
            (entry["storeAssertionRecords"] as? [[String: Any]]).map { !$0.isEmpty } ?? false
        }
    }
}

/// MM:SS from a number of seconds.
func formatTime(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

func phaseColor(_ phase: PomodoroPhase) -> Color {
    switch phase {
    case .work: return .capeRed
    case .shortBreak: return Color(red: 0.3, green: 0.85, blue: 0.45)
    case .longBreak: return Color(red: 0.35, green: 0.6, blue: 1.0)
    }
}
