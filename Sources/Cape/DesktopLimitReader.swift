import Foundation

/// Reads the usage-limit reset time straight from the Claude **desktop app**'s
/// storage, for users who work in the desktop app (whose chat never runs a
/// statusLine, so the normal ratelimit.json is never written).
///
/// When a limit is hit and auto-resume is queued, the desktop app persists a
/// `LSS-persisted.autoResumeRateLimit.<id>` key holding
/// `{"resetsAt":<unix epoch>,...}` in its Local Storage LevelDB. There is no
/// public API for this, so we byte-scan those files — best effort, and may stop
/// working if the desktop app changes how it stores this.
enum DesktopLimitReader {
    private static var leveldbDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Local Storage/leveldb")
    }

    private static let pattern = try? NSRegularExpression(
        pattern: "autoResumeRateLimit[\\s\\S]{0,120}?\"resetsAt\":(\\d+)")

    /// Most recently written reset time, or nil if none is stored.
    static func resetsAt() -> Date? {
        guard let pattern,
              let files = try? FileManager.default.contentsOfDirectory(
                at: leveldbDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }

        // Newest file first — LevelDB appends the current value to the latest log.
        let ordered = files
            .filter { ["log", "ldb"].contains($0.pathExtension) }
            .sorted { mtime($0) > mtime($1) }

        for file in ordered {
            guard let data = try? Data(contentsOf: file),
                  let text = String(data: data, encoding: .isoLatin1) else { continue }
            let all = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let last = all.last, let r = Range(last.range(at: 1), in: text),
               let epoch = TimeInterval(text[r]) {
                return Date(timeIntervalSince1970: epoch)   // newest file's latest value
            }
        }
        return nil
    }

    private static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
