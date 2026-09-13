import SwiftUI
import AppKit

extension Color {
    /// The app's coral accent (#FA834D) — used for Claude, the copy flash, etc.
    static let coral = Color(red: 0.980, green: 0.514, blue: 0.302)
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
    case .work: return Color(red: 1.0, green: 0.35, blue: 0.35)
    case .shortBreak: return Color(red: 0.3, green: 0.85, blue: 0.45)
    case .longBreak: return Color(red: 0.35, green: 0.6, blue: 1.0)
    }
}
