import Foundation

/// Handles the hidden `cape statusline` subcommand.
///
/// Claude Code invokes a configured `statusLine` command on every UI render and
/// pipes a JSON blob to it on stdin. That blob is the *only* place Claude Code
/// exposes `rate_limits.*.resets_at` (the Unix epoch when a usage window frees
/// up) — it is not in any hook event or on-disk state. So we install this
/// executable as the statusLine command: it captures the reset times to a small
/// file the app reads, and prints a compact footer back for the terminal.
///
/// It runs as a plain CLI — `main.swift` routes here and exits before any AppKit
/// setup, so no window, Dock icon, or second instance is ever created.
enum StatusLine {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        persistRateLimits(obj)
        FileHandle.standardOutput.write(Data(footer(obj).utf8))
    }

    private static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/cape")
    }

    // MARK: - Capture

    /// Merge whatever rate-limit fields are present into ratelimit.json. The
    /// block is "Only present for subscribers after first API response", so on
    /// renders where it is absent we leave the last known values untouched.
    private static func persistRateLimits(_ obj: [String: Any]) {
        guard let rl = obj["rate_limits"] as? [String: Any], !rl.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ratelimit.json")

        var out = (try? JSONSerialization.jsonObject(with: (try? Data(contentsOf: file)) ?? Data())) as? [String: Any] ?? [:]
        out["updated_at"] = Date().timeIntervalSince1970
        if let f = rl["five_hour"] as? [String: Any] {
            if let r = f["resets_at"] { out["five_hour_resets_at"] = r }
            if let u = f["used_percentage"] { out["five_hour_used"] = u }
        }
        if let s = rl["seven_day"] as? [String: Any] {
            if let r = s["resets_at"] { out["seven_day_resets_at"] = r }
            if let u = s["used_percentage"] { out["seven_day_used"] = u }
        }
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            try? data.write(to: file)
        }
    }

    // MARK: - Footer

    /// `Opus 4.8  ·  project-006-notch  ·  main  ·  ctx 42%  ·  5h 63%  ·  wk 21%`
    private static func footer(_ obj: [String: Any]) -> String {
        var parts: [String] = []
        if let model = obj["model"] as? [String: Any], let name = model["display_name"] as? String {
            parts.append(name)
        }
        if let ws = obj["workspace"] as? [String: Any], let cwd = ws["current_dir"] as? String {
            parts.append((cwd as NSString).lastPathComponent)
            if let branch = gitBranch(cwd) { parts.append(branch) }
        }
        if let cw = obj["context_window"] as? [String: Any], let used = cw["used_percentage"] as? Double {
            parts.append("ctx \(Int(used.rounded()))%")
        }
        if let rl = obj["rate_limits"] as? [String: Any] {
            if let f = rl["five_hour"] as? [String: Any], let u = f["used_percentage"] as? Double {
                parts.append("5h \(Int(u.rounded()))%")
            }
            if let s = rl["seven_day"] as? [String: Any], let u = s["used_percentage"] as? Double {
                parts.append("wk \(Int(u.rounded()))%")
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Current branch, read straight from `.git/HEAD` (no subprocess). Returns
    /// nil for a detached HEAD or a worktree/submodule where `.git` is a file.
    private static func gitBranch(_ cwd: String) -> String? {
        let head = (cwd as NSString).appendingPathComponent(".git/HEAD")
        guard let s = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        guard t.hasPrefix(prefix) else { return nil }
        return String(t.dropFirst(prefix.count))
    }
}
