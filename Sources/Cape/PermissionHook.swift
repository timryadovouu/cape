import Foundation

/// The hidden `cape permission` subcommand — Claude Code's PermissionRequest
/// hook. Claude runs it right before it would ask "Allow this?" and waits for it.
///
/// It logs the request to the event log (so the notch shows the session as
/// waiting), hands it to the running Cape as a file in `pending/`, and waits for
/// Cape to write the answer next to it. Allow / Deny go back to Claude Code as
/// the hook's decision. With no answer in time — or no Cape running, or the
/// feature off — it exits silently and Claude asks in the terminal / app as usual.
///
/// Questions (AskUserQuestion) and plan approval (ExitPlanMode) are passed
/// straight through: they need the real dialog, the notch only shows them.
enum PermissionHook {
    static let passThrough: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    static var dir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/cape") }
    static var pendingDir: URL { dir.appendingPathComponent("pending", isDirectory: true) }
    /// Cape's heartbeat + approval settings, rewritten every few seconds while it runs.
    static var stateFile: URL { dir.appendingPathComponent("cape.json") }

    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let request = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { return }
        log(input)

        let tool = request["tool_name"] as? String ?? ""
        guard !passThrough.contains(tool), let timeout = liveTimeout() else { return }

        let id = UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        let requestFile = pendingDir.appendingPathComponent("\(id).json")
        let answerFile = pendingDir.appendingPathComponent("\(id).answer")
        var pending = request
        pending["cape_id"] = id
        pending["cape_created"] = Date().timeIntervalSince1970
        pending["cape_timeout"] = timeout
        pending["cape_app"] = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
        guard let data = try? JSONSerialization.data(withJSONObject: pending),
              (try? data.write(to: requestFile)) != nil else { return }
        defer { try? fm.removeItem(at: requestFile); try? fm.removeItem(at: answerFile) }

        // Wait for the notch — until the timeout, or Cape quits.
        let deadline = Date().addingTimeInterval(timeout)
        var lastCheck = Date()
        while Date() < deadline {
            if let answer = try? String(contentsOf: answerFile, encoding: .utf8) {
                respond(answer.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            if Date().timeIntervalSince(lastCheck) > 5 {
                lastCheck = Date()
                if liveTimeout() == nil { return }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// The timeout to wait, if a Cape is running with notch approvals on.
    private static func liveTimeout() -> TimeInterval? {
        guard let data = try? Data(contentsOf: stateFile),
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let updated = state["updated"] as? Double,
              Date().timeIntervalSince1970 - updated < 15,
              state["approvals"] as? Bool == true else { return nil }
        return state["timeout"] as? Double ?? 60
    }

    /// "allow" / "deny" become the hook's decision; anything else ("skip" —
    /// answer it in the terminal instead) prints nothing.
    private static func respond(_ answer: String) {
        let decision: [String: Any]
        switch answer {
        case "allow": decision = ["behavior": "allow"]
        case "deny": decision = ["behavior": "deny", "message": "Denied from the Cape notch."]
        default: return
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            FileHandle.standardOutput.write(data)
        }
    }

    /// Same line format as the other hooks: `{"cape_app": "<bundle id>", "event": {…}}`.
    private static func log(_ event: Data) {
        let app = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
        guard let compact = (try? JSONSerialization.jsonObject(with: event))
                .flatMap({ try? JSONSerialization.data(withJSONObject: ["cape_app": app, "event": $0]) }),
              let handle = try? FileHandle(forWritingTo: dir.appendingPathComponent("events.jsonl")) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(compact + Data("\n".utf8))
    }
}
