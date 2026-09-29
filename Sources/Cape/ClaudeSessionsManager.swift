import Foundation
import AppKit
import SwiftUI

/// A Claude Code session, as seen through its hook events.
struct ClaudeSession: Identifiable, Equatable {
    enum Status: Equatable {
        case working          // between your prompt and Stop
        case permission       // wants to run a tool — Allow / Deny in the notch
        case asking           // asked a question / has a plan — answer it there
        case waiting          // waiting for you in the terminal / app (a prompt Cape can't answer)
        case done             // finished its turn
    }
    let id: String
    var project: String       // the working folder's name
    var status: Status
    var since: Date           // when the status last changed
    var lastEvent: Date
    var prompt: String?       // your last prompt, first line
    var app: String?          // bundle id of the app it runs in (iTerm2, Claude, …)
    var title: String?        // the Claude app's name for the session (Code tab only)
    var transcript: String?   // the conversation file Claude keeps writing while it works
    /// A finished turn you've looked at: opened from the list, switched to its
    /// app, or it finished while that app was in front. Until then Clawd waits.
    var seen = true

    var needsYou: Bool { status == .permission || status == .asking || status == .waiting }
}

/// How Clawd leaves: home, behind the camera (he waited long enough, or the
/// app quit), or with a happy hop (you came to look).
enum ClawdExit: Equatable { case home, happy }

/// One Clawd in the island — for one finished session you haven't looked at.
struct ClawdSlot: Identifiable, Equatable {
    let id: String            // the session's
    var asleep = false        // waited past Settings › Claude's "falls asleep after"
    var leaving: ClawdExit?   // on his way out (kept a moment for the animation)
}

/// A tool call waiting for Allow / Deny (a file in ~/.claude/cape/pending,
/// written by the `cape permission` hook, which waits for the answer).
struct ClaudePermission: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let tool: String
    let detail: String        // the command, the file, the URL…
    let expires: Date
}

/// Watches the event log that Claude Code's hooks append to: which sessions are
/// working, finished, or waiting for you — and the permission requests the
/// notch can answer. Drives the Claude island beside the camera and the
/// sessions list that drops down from it.
final class ClaudeSessionsManager: ObservableObject {
    @Published private(set) var anyWorking = false
    /// Some session waits for you (a permission, a question, a plan).
    @Published private(set) var needsYou = false
    /// Sessions active in the last few hours, most urgent first.
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var permissions: [ClaudePermission] = []
    /// A Clawd for each session that finished while you were away (up to four,
    /// oldest first), plus the ones just leaving.
    @Published private(set) var clawds: [ClawdSlot] = []
    static let maxClawds = 4
    /// Sessions you came to look at — their Clawd leaves with a happy hop.
    private var happyExits: Set<String> = []

    /// When the exhausted/near-limit usage window frees up. nil when every window
    /// is below the configured threshold (Claude is available). Fed by
    /// ratelimit.json, which our statusLine command writes.
    @Published private(set) var limitResetAt: Date?
    /// True when the binding window is actually at/over 100% (Claude is blocked),
    /// vs merely past the "show" threshold. Drives the wording in the Timer tab.
    @Published private(set) var limitBlocked = false

    /// A session is dropped from "working" if neither an event nor its transcript
    /// moved for this long (guards against one that never emits Stop — a crash).
    /// A long turn keeps writing its transcript, so it stays "working".
    private let workingTimeout: TimeInterval = 10 * 60
    /// How much of the log's end to replay at launch, to pick up running sessions.
    private let replayBytes: UInt64 = 512 * 1024
    private var replaying = false

    private let settings: Settings
    private var byID: [String: ClaudeSession] = [:]
    /// Sessions that ended or went quiet this long ago drop off the list.
    private let staleAfter: TimeInterval = 3 * 3600
    /// A finished session leaves the list this long after it finished (or at
    /// once, when you open it from the list).
    private let doneFor: TimeInterval = 15 * 60
    private var lastHeartbeat = Date.distantPast
    private var workspaceObservers: [NSObjectProtocol] = []
    private var offset: UInt64 = 0
    private var timer: Timer?

    // Desktop-app fallback source (throttled — it scans LevelDB files).
    private var lastDesktopRead = Date.distantPast
    private var desktopReset: Date?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var dir: URL { home.appendingPathComponent(".claude/cape") }
    private var eventsFile: URL { dir.appendingPathComponent("events.jsonl") }
    private var rateLimitFile: URL { dir.appendingPathComponent("ratelimit.json") }
    private var settingsFile: URL { home.appendingPathComponent(".claude/settings.json") }

    /// `live: false` (the screenshot tool): read nothing, touch no hooks — the
    /// sessions come from `showDemo`.
    init(settings: Settings, live: Bool = true) {
        self.settings = settings
        guard live else { return }
        // Replay the end of the log to find sessions already running; `settle()`
        // then dates them by their transcripts, so finished ones don't come back
        // as "thinking" (the island would hang after a relaunch).
        if let size = (try? FileManager.default.attributesOfItem(atPath: eventsFile.path))?[.size] as? NSNumber {
            offset = size.uint64Value > replayBytes ? size.uint64Value - replayBytes : 0
            replaying = true
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Switching to the app a session runs in counts as having looked at it;
        // quitting that app ends its sessions.
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in self?.appActivated(Self.bundleID(note))
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in self?.appQuit(Self.bundleID(note))
            },
        ]
        // Bring the hooks up to date (new events, a moved app) when tracking is on.
        DispatchQueue.main.async { [weak self] in
            guard let self, settings.trackClaude, self.hooksNeedUpdate() else { return }
            self.installHooks()
        }
    }

    deinit {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private static func bundleID(_ note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    /// Switching to a session's app counts as looking at it — after a moment:
    /// to quit an app or close its window you switch to it first, and then Clawd
    /// should go home, not hop for joy. So if the session ends or the app quits
    /// within that moment, he walks home; otherwise the happy hop.
    private func appActivated(_ id: String?) {
        guard let id, byID.values.contains(where: { $0.status == .done && !$0.seen && $0.app == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id else { return }
            var changed = false
            for (key, s) in self.byID where s.status == .done && !s.seen && s.app == id {
                self.byID[key]?.seen = true
                self.happyExits.insert(key)
                changed = true
            }
            if changed { self.recompute() }
        }
    }

    private func appQuit(_ id: String?) {
        guard let id else { return }
        let before = byID.count
        byID = byID.filter { $0.value.app != id }
        if byID.count != before { recompute() }
    }

    // MARK: - Reading events

    private func poll() {
        if let handle = try? FileHandle(forReadingFrom: eventsFile) {
            defer { try? handle.close() }
            let end = (try? handle.seekToEnd()) ?? 0
            if end < offset { offset = 0; byID = [:] }   // rotated/truncated
            if end > offset {
                try? handle.seek(toOffset: offset)
                var data = handle.readDataToEndOfFile()
                // Whole lines only: the hook writes a line in pieces (the wrapper,
                // the event, the closing brace), and a line caught half-written
                // would be lost — a lost Stop left the island "thinking". The rest
                // is read next time, once it's complete.
                let cut = data.lastIndex(of: UInt8(ascii: "\n")).map { $0 - data.startIndex + 1 } ?? 0
                data = data.prefix(cut)
                offset += UInt64(cut)
                // A hook input that ended in a newline pushed the wrapper's closing
                // "}" onto a line of its own — glue such a line back on.
                var previous: String?
                for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
                    let text = String(line)
                    if text.trimmingCharacters(in: .whitespaces) == "}", let head = previous {
                        process(head + "}")
                    } else {
                        process(text)
                    }
                    previous = text
                }
            }
        }
        if replaying { settle() }
        readPermissions()
        recompute()
        readRateLimit()
        heartbeat()
    }

    /// Screenshot tool: show these instead of real sessions.
    func showDemo(_ demo: [ClaudeSession], _ requests: [ClaudePermission]) {
        sessions = demo
        permissions = requests
        needsYou = demo.contains(where: \.needsYou)
        anyWorking = demo.contains { $0.status == .working }
        let sleepAfter = TimeInterval(settings.claudeMascotSleepMinutes * 60)
        clawds = demo.filter { $0.status == .done && !$0.seen }.sorted { $0.since < $1.since }
            .map { ClawdSlot(id: $0.id, asleep: Date().timeIntervalSince($0.since) >= sleepAfter) }
    }

    /// After the launch replay: the log has no timestamps, so date each session
    /// by its transcript's last write. Quiet ones are finished; one that was
    /// "waiting" has no pending request anymore unless it's still fresh.
    private func settle() {
        replaying = false
        let now = Date()
        for (id, var s) in byID {
            guard let active = activity(s) else { byID[id] = nil; continue }
            s.lastEvent = active
            s.since = active
            if s.status != .done && now.timeIntervalSince(active) > 120 { s.status = .done }
            byID[id] = s
        }
    }

    /// When the session last showed life: its transcript's last write.
    private func activity(_ s: ClaudeSession) -> Date? {
        guard let path = s.transcript else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Update the limit-reset state. Prefer the statusLine data (terminal Claude
    /// Code); if that file doesn't exist — e.g. the user works in the desktop app
    /// — fall back to the desktop app's own Local Storage.
    private func readRateLimit() {
        guard settings.trackClaude else { setLimit(reset: nil, blocked: false); return }
        // Terminal statusLine data — used only while it's fresh (a terminal Claude
        // Code session is actively rendering). Once that goes stale we fall through
        // to the desktop app, so using both never lets a closed terminal's old
        // snapshot shadow the live desktop one.
        if let o = (try? Data(contentsOf: rateLimitFile))
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
           let updated = o["updated_at"] as? Double,
           Date().timeIntervalSince1970 - updated < 600 {
            let (reset, blocked) = statusLineLimit(o)
            setLimit(reset: reset, blocked: blocked)
            return
        }
        // Desktop fallback: scanning the LevelDB is heavier, so throttle it.
        if Date().timeIntervalSince(lastDesktopRead) > 15 {
            lastDesktopRead = Date()
            desktopReset = DesktopLimitReader.resetsAt()
        }
        // No usage % is available from the desktop store, so don't claim Claude
        // is blocked — "limits reset at HH:MM" reads honestly whether or not it is.
        setLimit(reset: desktopReset, blocked: false)
    }

    /// The 5-hour window's reset from statusLine data, shown as soon as the window
    /// is used at all (nil if untouched). `blocked` is true once it hits 100%.
    private func statusLineLimit(_ o: [String: Any]) -> (Date?, Bool) {
        guard let used = o["five_hour_used"] as? Double, used > 0,
              let epoch = o["five_hour_resets_at"] as? Double else { return (nil, false) }
        return (Date(timeIntervalSince1970: epoch), used >= 100)
    }

    private func setLimit(reset: Date?, blocked: Bool) {
        if reset != limitResetAt { limitResetAt = reset }
        if blocked != limitBlocked { limitBlocked = blocked }
    }

    private func process(_ line: String) {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        // Current format wraps the hook input with the host app's bundle id:
        // {"cape_app": "...", "event": {...}}; older lines are the bare input.
        let obj = raw["event"] as? [String: Any] ?? raw
        let app = (raw["cape_app"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let id = obj["session_id"] as? String,
              let event = obj["hook_event_name"] as? String else { return }
        let now = Date()
        if event == "SessionEnd" { byID[id] = nil; return }

        let cwd = obj["cwd"] as? String ?? ""
        var s = byID[id] ?? ClaudeSession(id: id, project: (cwd as NSString).lastPathComponent,
                                          status: .done, since: now, lastEvent: now, prompt: nil, app: app)
        if !cwd.isEmpty { s.project = (cwd as NSString).lastPathComponent }
        if let app { s.app = app }
        if let transcript = obj["transcript_path"] as? String { s.transcript = transcript }
        if s.app == DesktopSessions.bundleID, let title = desktop.info(for: id)?.title { s.title = title }
        s.lastEvent = now
        func set(_ status: ClaudeSession.Status) {
            if s.status != status { s.status = status; s.since = now }
        }

        switch event {
        case "UserPromptSubmit":
            if s.status == .done && !s.seen { happyExits.insert(id) }     // back at it: you saw it
            set(.working)
            s.seen = true
            s.since = now
            if let prompt = obj["prompt"] as? String {
                let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
                s.prompt = line.trimmingCharacters(in: .whitespaces)
            }
        case "Stop":
            // Finished in front of you (its app is frontmost), or long ago (the
            // launch replay): nothing to wait for. Otherwise Clawd waits.
            if s.status != .done {
                s.seen = replaying || s.app == NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
            set(.done)
        case "PermissionRequest":
            let tool = obj["tool_name"] as? String ?? ""
            set(PermissionHook.passThrough.contains(tool) ? .asking : .permission)
        case "PostToolUse":
            // Only hooked for the question / plan tools: answered, back to work.
            set(.working)
        case "Notification":
            let type = obj["notification_type"] as? String
            let message = obj["message"] as? String ?? ""
            if ["permission_prompt", "elicitation_dialog", "agent_needs_input"].contains(type ?? "")
                || (type == nil && message.hasPrefix("Claude needs your permission")) {
                if s.status == .working || s.status == .permission { set(.waiting) }
            }
        default:
            break   // SessionStart, SubagentStop: just seen
        }
        byID[id] = s
    }

    /// Requests the `cape permission` hook is waiting on (it deletes the file
    /// once answered or timed out — then the session is back to working, or
    /// waiting in the terminal).
    private func readPermissions() {
        let dir = PermissionHook.pendingDir
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found: [ClaudePermission] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = o["cape_id"] as? String, let session = o["session_id"] as? String,
                  let created = o["cape_created"] as? Double else { continue }
            let expires = Date(timeIntervalSince1970: created + (o["cape_timeout"] as? Double ?? 60))
            if expires < Date().addingTimeInterval(-30) { try? FileManager.default.removeItem(at: file); continue }
            let tool = o["tool_name"] as? String ?? "Tool"
            found.append(ClaudePermission(id: id, sessionID: session, tool: tool,
                                          detail: Self.describe(tool, o["tool_input"] as? [String: Any] ?? [:]),
                                          expires: expires))
        }
        found.sort { $0.expires < $1.expires }
        // A request that just disappeared was answered (here, or it timed out to the terminal).
        for gone in permissions where !found.contains(where: { $0.id == gone.id }) {
            if var s = byID[gone.sessionID], s.status == .permission,
               !found.contains(where: { $0.sessionID == gone.sessionID }) {
                s.status = answered.remove(gone.id) != nil ? .working : .waiting
                s.since = Date()
                byID[gone.sessionID] = s
            }
        }
        if found != permissions { permissions = found }
    }

    /// Ids answered from the notch (vs. timed out to the terminal).
    private var answered: Set<String> = []

    /// Allow / Deny from the notch; `nil` hands it back to the terminal / app.
    func answer(_ request: ClaudePermission, allow: Bool?) {
        let text = allow.map { $0 ? "allow" : "deny" } ?? "skip"
        if allow != nil { answered.insert(request.id) }
        try? text.write(to: PermissionHook.pendingDir.appendingPathComponent("\(request.id).answer"),
                        atomically: true, encoding: .utf8)
        readPermissions()
        recompute()
    }

    /// One line describing what the tool wants to do.
    private static func describe(_ tool: String, _ input: [String: Any]) -> String {
        for key in ["command", "file_path", "notebook_path", "url", "pattern", "path", "query", "description"] {
            if let v = input[key] as? String, !v.isEmpty {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                return v.replacingOccurrences(of: home, with: "~")
            }
        }
        return input.keys.sorted().first.map { "\($0): …" } ?? ""
    }

    /// Bring the session forward: in the Claude app, straight into that session's
    /// conversation (its own `claude://code/continue` link); a terminal just comes
    /// to the front.
    func focus(_ session: ClaudeSession) {
        // Opening a finished session means you've seen it: off the list (it comes
        // back with its next event).
        if session.status == .done {
            if !session.seen { happyExits.insert(session.id) }
            byID[session.id] = nil
            recompute()
        }
        if session.app == DesktopSessions.bundleID, let local = desktop.info(for: session.id)?.localID,
           let url = URL(string: "claude://code/continue?session=\(local)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let id = session.app,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return }
        app.activate()
    }

    private let desktop = DesktopSessions()

    /// Tell the hooks Cape is alive, and whether / how long to wait for the notch.
    private func heartbeat() {
        guard Date().timeIntervalSince(lastHeartbeat) > 4 else { return }
        lastHeartbeat = Date()
        let state: [String: Any] = [
            "updated": Date().timeIntervalSince1970,
            "approvals": settings.trackClaude && settings.claudeApprovals,
            "timeout": Double(settings.claudeApprovalTimeout),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: PermissionHook.stateFile, options: .atomic)
        }
    }

    /// The last finish chime, held so it isn't freed mid-play.
    private var chime: NSSound?

    private func recompute() {
        let now = Date()
        // A finished session you've seen leaves after `doneFor`; one you haven't
        // stays with Clawd for as long as Settings › Claude says, then leaves too.
        let mascot = settings.claudeMascot
        let waitFor = TimeInterval(settings.claudeMascotMinutes * 60)
        byID = byID.filter {
            let s = $0.value
            guard now.timeIntervalSince(s.lastEvent) < staleAfter else { return false }
            guard s.status == .done else { return true }
            return now.timeIntervalSince(s.since) < (mascot && !s.seen ? waitFor : doneFor)
        }       // (a Clawd whose session left without being looked at goes home)
        // A "working" session that went silent — no event and no transcript write
        // for a while (crashed, never sent Stop) — stops counting.
        for (id, s) in byID where s.status == .working && now.timeIntervalSince(s.lastEvent) > workingTimeout {
            if let active = activity(s), now.timeIntervalSince(active) < workingTimeout { continue }
            byID[id]?.status = .done
            byID[id]?.seen = true       // not a real finish — nothing for Clawd
        }
        let rank: [ClaudeSession.Status: Int] = [.permission: 0, .asking: 1, .waiting: 2, .working: 3, .done: 4]
        let list = byID.values.sorted {
            rank[$0.status]! != rank[$1.status]! ? rank[$0.status]! < rank[$1.status]! : $0.since > $1.since
        }
        if list != sessions { sessions = list }
        let attention = list.contains(where: \.needsYou)
        if attention != needsYou { needsYou = attention }
        updateClawds(list, now: now)
        let working = list.contains { $0.status == .working }
        if working != anyWorking {
            // The coral "thinking" island just went away — and not because it now waits for you.
            let stopped = anyWorking && !working && !attention
            anyWorking = working
            if stopped { playDoneSound() }
        }
    }

    /// One Clawd per unseen finished session, in the order they finished. One
    /// that's no longer due stays a moment, marked leaving, for his exit.
    private func updateClawds(_ list: [ClaudeSession], now: Date) {
        guard settings.trackClaude, settings.claudeMascot else {
            if !clawds.isEmpty { clawds = [] }
            happyExits = []
            return
        }
        let sleepAfter = TimeInterval(settings.claudeMascotSleepMinutes * 60)
        let unseen = list.filter { $0.status == .done && !$0.seen }
            .sorted { $0.since < $1.since }
            .suffix(Self.maxClawds)
        func slot(_ s: ClaudeSession) -> ClawdSlot {
            ClawdSlot(id: s.id, asleep: now.timeIntervalSince(s.since) >= sleepAfter)
        }
        var next = clawds.map { old -> ClawdSlot in
            if let s = unseen.first(where: { $0.id == old.id }) { return slot(s) }
            var gone = old
            if gone.leaving == nil {
                let exit: ClawdExit = happyExits.remove(old.id) != nil ? .happy : .home
                gone.leaving = exit
                DispatchQueue.main.asyncAfter(deadline: .now() + (exit == .happy ? 0.8 : 2.9)) { [weak self] in
                    self?.clawds.removeAll { $0.id == old.id && $0.leaving != nil }
                }
            }
            return gone
        }
        for s in unseen where !next.contains(where: { $0.id == s.id }) { next.append(slot(s)) }
        // Going home is to the left, behind the camera: step to the front of the
        // line first, so he doesn't walk through the others.
        let home = next.filter { $0.leaving == .home }
        next = home + next.filter { $0.leaving != .home }
        happyExits = happyExits.filter { id in next.contains { $0.id == id } || byID[id] != nil }
        if next != clawds {
            let reordered = next.map(\.id) != clawds.map(\.id)
            withAnimation(reordered ? .easeInOut(duration: 0.35) : nil) { clawds = next }
        }
    }

    /// Chime when Claude finishes thinking (opt-in).
    private func playDoneSound() {
        guard settings.trackClaude, settings.claudeSound else { return }
        // Quiet during Focus/DND unless the user opts in.
        if !settings.claudeSoundDuringDND && FocusMonitor.isActive { return }
        // Quiet while the Claude app is front — you can already see it finish.
        if settings.claudeSoundMuteWhenFront,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier?
               .hasPrefix("com.anthropic.") == true {
            return
        }
        let s = NSSound(named: settings.claudeSoundName) ?? NSSound(named: "Funk")
        chime = s
        s?.stop(); s?.play()
    }

    // MARK: - Setup

    /// Merge our hooks into ~/.claude/settings.json (backed up first).
    @discardableResult
    func installHooks() -> Bool {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsFile) {
            try? data.write(to: settingsFile.appendingPathExtension("bak"))
            root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "cape"
        // Drop our older entries (an earlier log format, or another app path), then add the current ones.
        for (event, value) in hooks {
            guard var arr = value as? [[String: Any]] else { continue }
            arr = arr.compactMap { g in
                var g = g
                let kept = (g["hooks"] as? [[String: Any]] ?? []).filter { !Self.isOurs($0["command"] as? String) }
                if kept.isEmpty { return nil }
                g["hooks"] = kept
                return g
            }
            hooks[event] = arr.isEmpty ? nil : arr
        }
        for (event, entry) in Self.hookEntries(exe: exe) {
            var arr = hooks[event] as? [[String: Any]] ?? []
            arr.append(entry)
            hooks[event] = arr
        }
        root["hooks"] = hooks

        // statusLine: the only source of the usage-limit reset times. Point it at
        // our own executable's hidden `statusline` subcommand.
        root["statusLine"] = ["type": "command", "command": "\"\(exe)\" statusline"]

        guard let out = try? JSONSerialization.data(withJSONObject: root,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return false }
        do { try out.write(to: settingsFile); return true } catch { return false }
    }

    /// Log every event, with the host app's bundle id so a click can bring it forward
    /// — one line each (the input's own trailing newline is dropped; newlines
    /// inside it are escaped in JSON, so none are lost).
    private static let logCommand = "mkdir -p \"$HOME/.claude/cape\" && { printf '{\"cape_app\":\"%s\",\"event\":' \"$__CFBundleIdentifier\"; tr -d '\\n'; echo '}'; } >> \"$HOME/.claude/cape/events.jsonl\""

    private static func isOurs(_ command: String?) -> Bool {
        guard let c = command else { return false }
        return c.contains(".claude/cape/events.jsonl") || c.hasSuffix("\" permission")
    }

    /// Hook groups by event: the log everywhere; PermissionRequest runs our own
    /// executable, which waits for the notch (so it gets a long timeout); the
    /// question / plan tools also report when they're answered.
    private static func hookEntries(exe: String) -> [(String, [String: Any])] {
        let log: [String: Any] = ["hooks": [["type": "command", "command": logCommand]]]
        var entries = ["UserPromptSubmit", "Stop", "Notification", "SessionStart", "SessionEnd", "SubagentStop"]
            .map { ($0, log) }
        entries.append(("PermissionRequest", ["hooks": [["type": "command", "command": "\"\(exe)\" permission",
                                                         "timeout": 660]]]))
        entries.append(("PostToolUse", ["matcher": "AskUserQuestion|ExitPlanMode",
                                        "hooks": [["type": "command", "command": logCommand]]]))
        return entries
    }

    /// Our hooks are missing or from an older version / app location — reinstall.
    func hooksNeedUpdate() -> Bool {
        guard let data = try? Data(contentsOf: settingsFile),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return true }
        let exe = Bundle.main.executableURL?.path ?? ""
        for (event, entry) in Self.hookEntries(exe: exe) {
            let want = ((entry["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
            let has = (hooks[event] as? [[String: Any]] ?? []).contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == want }
            }
            if !has { return true }
        }
        return false
    }
}

/// The Claude app's own records of its Code sessions — each links the id the
/// hooks see (`cliSessionId`, plus earlier ones) to the app's `local_…` id, which
/// its `claude://code/continue?session=` link opens, and the session's title.
final class DesktopSessions {
    static let bundleID = "com.anthropic.claudefordesktop"
    struct Info { let localID: String; let title: String? }

    private var byCLI: [String: Info] = [:]
    private var lastScan = Date.distantPast
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")

    /// Looked up in a cache; a miss rescans (at most every 5 s).
    func info(for cliID: String) -> Info? {
        if let hit = byCLI[cliID] { return hit }
        guard Date().timeIntervalSince(lastScan) > 5 else { return nil }
        scan()
        return byCLI[cliID]
    }

    private func scan() {
        lastScan = Date()
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for account in accounts {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file),
                          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let local = o["sessionId"] as? String else { continue }
                    let info = Info(localID: local, title: (o["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
                    var ids = o["priorCliSessionIds"] as? [String] ?? []
                    if let cli = o["cliSessionId"] as? String { ids.append(cli) }
                    for id in ids { byCLI[id] = info }
                }
            }
        }
    }
}
