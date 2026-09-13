import AppKit

enum MediaSource: String {
    case none, spotify, cmus
}

/// Now-playing info and transport controls.
///
/// Uses Spotify's AppleScript interface when Spotify is running, otherwise
/// falls back to `cmus-remote` if cmus is running. Both avoid private APIs.
final class MediaController: ObservableObject {
    @Published private(set) var source: MediaSource = .none
    @Published private(set) var title: String = ""
    @Published private(set) var artist: String = ""
    @Published private(set) var isPlaying: Bool = false

    private var timer: Timer?
    private let queue = DispatchQueue(label: "io.cape.media")
    private lazy var cmusRemote = Self.findCmusRemote()

    init() {
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Spotify posts this the instant playback changes — no polling lag on ⏯.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] _ in self?.poll() }
        poll()
    }

    // MARK: - Polling

    private var spotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    private func poll() {
        let spotify = spotifyRunning
        let remote = cmusRemote
        queue.async { [weak self] in
            guard let self else { return }
            if spotify, let info = self.readSpotify() {
                self.publish(.spotify, info)
            } else if let remote, let info = self.readCmus(remote) {
                self.publish(.cmus, info)
            } else {
                self.publish(.none, ("", "", false))
            }
        }
    }

    private func publish(_ source: MediaSource, _ info: (String, String, Bool)) {
        DispatchQueue.main.async {
            self.source = source
            self.title = info.0
            self.artist = info.1
            self.isPlaying = info.2
        }
    }

    // MARK: - Spotify

    private func readSpotify() -> (String, String, Bool)? {
        // Single-line `to return` form — the multi-line variant fails to parse
        // via `osascript -e`. The "\t" below is a real tab char in the source.
        let script = "tell application \"Spotify\" to return (player state as text)"
            + " & \"\t\" & (name of current track) & \"\t\" & (artist of current track)"
        guard let out = Self.runOSA(script) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard parts.count == 3 else { return nil }
        return (parts[1], parts[2], parts[0] == "playing")
    }

    // MARK: - cmus

    private func readCmus(_ remote: String) -> (String, String, Bool)? {
        guard let out = Self.run(remote, ["-Q"]) else { return nil }
        var title = "", artist = "", status = ""
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("status ") { status = String(line.dropFirst(7)) }
            else if line.hasPrefix("tag title ") { title = String(line.dropFirst(10)) }
            else if line.hasPrefix("tag artist ") { artist = String(line.dropFirst(11)) }
            else if title.isEmpty && line.hasPrefix("file ") {
                title = (line as NSString).lastPathComponent
            }
        }
        if title.isEmpty && artist.isEmpty { return nil }
        return (title, artist, status == "playing")
    }

    // MARK: - Controls

    func playPause() { control(spotify: "playpause", cmus: ["-u"]) }
    func next() { control(spotify: "next track", cmus: ["-n"]) }
    func previous() { control(spotify: "previous track", cmus: ["-r"]) }

    private func control(spotify: String, cmus: [String]) {
        let src = source
        let remote = cmusRemote
        queue.async { [weak self] in
            switch src {
            case .spotify: _ = Self.runOSA("tell application \"Spotify\" to \(spotify)")
            case .cmus: if let remote { _ = Self.run(remote, cmus) }
            case .none: break
            }
            DispatchQueue.main.async { self?.poll() }
        }
    }

    // MARK: - Process helpers

    private static func runOSA(_ script: String) -> String? {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findCmusRemote() -> String? {
        let candidates = ["/opt/homebrew/bin/cmus-remote",
                          "/usr/local/bin/cmus-remote",
                          "/usr/bin/cmus-remote"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
