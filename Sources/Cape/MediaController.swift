import AppKit
import AVFoundation
import MediaPlayer

enum MediaSource: String {
    case none, spotify, cmus

    /// How the player writes its own name ("cmus" is lowercase).
    var displayName: String { self == .cmus ? "cmus" : rawValue.capitalized }
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
    /// Playback position (s) as of `positionDate` — the view extrapolates from it
    /// between polls so the progress bar moves smoothly.
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var duration: Double = 0      // s; 0 = unknown
    /// Cover art for the current track — loaded once per track and kept here
    /// (not in the view), so reopening the notch shows it instantly.
    @Published private(set) var artwork: NSImage?

    /// One poll's worth of now-playing info.
    private struct NowPlaying {
        var title = "", artist = ""
        var isPlaying = false
        var position: Double = 0, duration: Double = 0
        var artworkURL: URL?      // Spotify: cover image on its CDN
        var file: String?         // cmus: path of the playing file
        var sampledAt = Date()    // when `position` was true (mid-way through the query)
    }

    private var artworkKey: String?                  // what `artwork` was loaded for
    private var artworkCache: [String: NSImage] = [:]
    private var artworkCacheOrder: [String] = []

    private var timer: Timer?
    private let queue = DispatchQueue(label: "io.cape.media")
    private lazy var cmusRemote = Self.findCmusRemote()

    /// Whether this instance may take media keys / Now Playing (not in the
    /// screenshot tool, which runs beside the real app and must never steer playback).
    private let mediaKeys: Bool

    init(mediaKeys: Bool = true) {
        self.mediaKeys = mediaKeys
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Spotify posts this the instant playback changes — no polling lag on ⏯.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] _ in self?.poll() }
        if mediaKeys { setupMediaKeys() }
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
            // The player measured its position somewhere during the query (which
            // takes 0.1–0.3 s) — date it to the middle, not to when we got it.
            func stamped(_ info: NowPlaying, since start: Date) -> NowPlaying {
                var i = info
                i.sampledAt = start.addingTimeInterval(Date().timeIntervalSince(start) / 2)
                return i
            }
            let start = Date()
            if spotify, let info = self.readSpotify() {
                self.publish(.spotify, stamped(info, since: start))
            } else if let remote, let info = self.readCmus(remote) {
                self.publish(.cmus, stamped(info, since: start))
            } else {
                self.publish(.none, NowPlaying())
            }
        }
    }

    private func publish(_ source: MediaSource, _ info: NowPlaying) {
        DispatchQueue.main.async {
            // Keep the bar gliding: while the same track keeps playing, a reading
            // within ~1.5 s of where we already are is just query jitter (or cmus's
            // whole-second position) — only re-anchor on a real jump (seek, pause,
            // new track). Re-anchoring every poll made the bar hop back a little.
            let sameTrack = source == self.source && info.title == self.title && info.artist == self.artist
            let predicted = self.position + (self.isPlaying ? info.sampledAt.timeIntervalSince(self.positionDate) : 0)
            let smooth = sameTrack && info.isPlaying && self.isPlaying && abs(info.position - predicted) < 1.5
            if !smooth {
                self.position = info.position
                self.positionDate = info.sampledAt
            }
            self.source = source
            self.title = info.title
            self.artist = info.artist
            self.isPlaying = info.isPlaying
            self.duration = info.duration
            self.updateArtwork(for: info)
            self.updateNowPlaying()
        }
    }

    // MARK: - Media keys (cmus)

    /// Media keys (F7 / F8 / F9, AirPods taps) go to macOS's "Now Playing" app.
    /// Spotify registers itself; cmus, a terminal program, can't — so while cmus
    /// is the source, Cape claims Now Playing and forwards the commands to
    /// `cmus-remote`. (It also puts the cmus track in Control Center.)
    private func setupMediaKeys() {
        let c = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping (MediaController) -> Void) {
            command.addTarget { [weak self] _ in
                guard let self, self.source == .cmus else { return .noActionableNowPlayingItem }
                action(self)
                return .success
            }
        }
        handle(c.togglePlayPauseCommand) { $0.playPause() }
        handle(c.playCommand) { if !$0.isPlaying { $0.playPause() } }
        handle(c.pauseCommand) { if $0.isPlaying { $0.playPause() } }
        handle(c.nextTrackCommand) { $0.next() }
        handle(c.previousTrackCommand) { $0.previous() }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, self.source == .cmus,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .noActionableNowPlayingItem }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private var claimsNowPlaying = false

    private func updateNowPlaying() {
        guard mediaKeys else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard source == .cmus else {
            if claimsNowPlaying {           // hand Now Playing back (e.g. to Spotify)
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
                claimsNowPlaying = false
            }
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:
                position + (isPlaying ? Date().timeIntervalSince(positionDate) : 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        claimsNowPlaying = true
    }

    // MARK: - Artwork

    /// Load cover art when the track changes: Spotify's image URL, or for cmus a
    /// cover file in the album folder / the art embedded in the audio file.
    private func updateArtwork(for info: NowPlaying) {
        let key = info.artworkURL?.absoluteString ?? info.file.map { ($0 as NSString).deletingLastPathComponent + "|" + $0 }
        guard key != artworkKey else { return }
        artworkKey = key
        guard let key else { artwork = nil; return }
        if let cached = artworkCache[key] { artwork = cached; return }
        artwork = nil
        Task { [weak self] in
            var image: NSImage?
            if let url = info.artworkURL {
                if let (data, _) = try? await URLSession.shared.data(from: url) { image = NSImage(data: data) }
            } else if let file = info.file {
                image = Self.folderCover(for: file)
                if image == nil { image = await Self.embeddedCover(for: file) }
            }
            await MainActor.run {
                guard let self, self.artworkKey == key else { return }   // track changed meanwhile
                if let image { self.cache(image, for: key) }
                self.artwork = image
                self.updateNowPlaying()     // cover into Control Center too (cmus)
            }
        }
    }

    private func cache(_ image: NSImage, for key: String) {
        artworkCache[key] = image
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)
        if artworkCacheOrder.count > 20 { artworkCache[artworkCacheOrder.removeFirst()] = nil }
    }

    /// cover / folder / front / album .jpg|.jpeg|.png next to the track (any case).
    private static func folderCover(for file: String) -> NSImage? {
        let dir = (file as NSString).deletingLastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        let bases = ["cover", "folder", "front", "album"]
        let exts = ["jpg", "jpeg", "png"]
        for base in bases {
            if let name = names.first(where: { n in
                let ns = n as NSString
                return ns.deletingPathExtension.lowercased() == base && exts.contains(ns.pathExtension.lowercased())
            }), let img = NSImage(contentsOfFile: (dir as NSString).appendingPathComponent(name)) {
                return img
            }
        }
        return nil
    }

    /// Art embedded in the audio file's tags (ID3 / MP4), if any.
    private static func embeddedCover(for file: String) async -> NSImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: file))
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue), let img = NSImage(data: data) { return img }
        }
        return nil
    }

    // MARK: - Spotify

    private func readSpotify() -> NowPlaying? {
        // Guard with `is running` *inside* the script: reading that property never
        // launches Spotify, and the `tell` only runs while it's alive — so quitting
        // Spotify (⌘Q) can't be relaunched by our poll. Single-line `to return`
        // form — the multi-line variant fails to parse via `osascript -e`. The "\t"
        // below is a real tab char in the source. Position goes out as whole
        // milliseconds so a locale's decimal comma can't garble it.
        let basic = "if application \"Spotify\" is running then tell application \"Spotify\" to return (player state as text)"
            + " & \"\t\" & (name of current track) & \"\t\" & (artist of current track)"
        let full = basic
            + " & \"\t\" & ((round (player position * 1000)) as text)"
            + " & \"\t\" & ((duration of current track) as text)"
            + " & \"\t\" & (artwork url of current track)"
        // If a Spotify build lacks one of the extra fields, fall back to the basics
        // rather than losing the player entirely.
        guard let out = Self.runOSA(full) ?? Self.runOSA(basic) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard parts.count >= 3 else { return nil }
        var info = NowPlaying(title: parts[1], artist: parts[2], isPlaying: parts[0] == "playing")
        if parts.count >= 6 {
            info.position = (Double(parts[3]) ?? 0) / 1000
            info.duration = (Double(parts[4]) ?? 0) / 1000
            info.artworkURL = URL(string: parts[5])
        }
        return info
    }

    // MARK: - cmus

    private func readCmus(_ remote: String) -> NowPlaying? {
        guard let out = Self.run(remote, ["-Q"]) else { return nil }
        var info = NowPlaying()
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("status ") { info.isPlaying = line.dropFirst(7) == "playing" }
            else if line.hasPrefix("tag title ") { info.title = String(line.dropFirst(10)) }
            else if line.hasPrefix("tag artist ") { info.artist = String(line.dropFirst(11)) }
            else if line.hasPrefix("duration ") { info.duration = Double(line.dropFirst(9)) ?? 0 }
            else if line.hasPrefix("position ") { info.position = Double(line.dropFirst(9)) ?? 0 }
            else if line.hasPrefix("file ") {
                info.file = String(line.dropFirst(5))
                if info.title.isEmpty { info.title = (line as NSString).lastPathComponent }
            }
        }
        if info.title.isEmpty && info.artist.isEmpty { return nil }
        return info
    }

    // MARK: - Controls

    func playPause() { control(spotify: "playpause", cmus: ["-u"]) }
    func next() { control(spotify: "next track", cmus: ["-n"]) }
    func previous() { control(spotify: "previous track", cmus: ["-r"]) }

    /// Jump to `seconds` into the track (whole seconds — locale-proof).
    func seek(to seconds: Double) {
        let s = max(0, Int(seconds.rounded()))
        position = Double(s)          // move the bar right away
        positionDate = Date()
        control(spotify: "set player position to \(s)", cmus: ["-k", "\(s)"])
    }

    private func control(spotify: String, cmus: [String]) {
        let src = source
        let remote = cmusRemote
        queue.async { [weak self] in
            switch src {
            case .spotify: _ = Self.runOSA("if application \"Spotify\" is running then tell application \"Spotify\" to \(spotify)")
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
