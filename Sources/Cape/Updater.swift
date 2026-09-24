import AppKit
import Security

/// In-app updates from GitHub Releases — no Apple Developer ID needed.
///
/// Check: ask the GitHub API for the latest (non-pre-)release and compare its tag
/// with our version. Install: download `Cape.zip`, unpack it next to the running
/// app, and **only if the new app is sealed by the same signing certificate as
/// this one** (our own designated requirement) swap it in and relaunch.
///
/// A file the app downloads itself isn't quarantined, so the update skips the
/// Gatekeeper "right-click → Open" dance; and since the certificate is the same,
/// macOS keeps the granted permissions.
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let notes: String
        let zipURL: URL?     // the "Cape.zip" asset (older releases were named differently)
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Called when a background check finds a new version (for the notch flash).
    var onUpdateFound: ((String) -> Void)?

    static let repo = "timryadovouu/cape"
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    var availableRelease: Release? {
        if case .available(let r) = state { return r }
        return nil
    }
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private let settings: Settings
    private var timer: Timer?
    private var announced: String?          // don't flash the same version twice
    private var progressObservation: NSKeyValueObservation?

    init(settings: Settings) {
        self.settings = settings
        // Background check shortly after launch, then every 6 hours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.backgroundCheck() }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.backgroundCheck() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func backgroundCheck() {
        guard settings.autoCheckUpdates, !isBusy, availableRelease == nil else { return }
        check(silent: true)
    }

    // MARK: - Check

    /// `silent`: a background check — stays quiet on "up to date" and errors.
    func check(silent: Bool = false) {
        guard !isBusy else { return }
        let before = state
        state = .checking
        Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await Self.fetchLatest()
                await MainActor.run {
                    if Self.isNewer(release.version, than: self.currentVersion) {
                        guard release.zipURL != nil else {
                            self.state = silent ? before : .failed("Cape \(release.version) has no Cape.zip to install — download it from GitHub.")
                            return
                        }
                        self.state = .available(release)
                        if self.announced != release.version {
                            self.announced = release.version
                            self.onUpdateFound?(release.version)
                        }
                    } else {
                        self.state = silent ? before : .upToDate
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = silent ? before : .failed(Self.message(error))
                }
            }
        }
    }

    private static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { throw UpdateError("Couldn't read the latest release from GitHub.") }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zipURL = assets.first(where: { ($0["name"] as? String) == "Cape.zip" })
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repo)/releases")!
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       zipURL: zipURL, page: page)
    }

    /// Compare the numeric part ("0.3.0" of "0.3.0-4-gabc") component by component.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Install

    func install(_ release: Release) {
        guard !isBusy, let zipURL = release.zipURL else { return }
        let appURL = Bundle.main.bundleURL

        // A quarantined app opened from Downloads runs from a read-only
        // "translocated" copy — it can't replace itself there.
        if appURL.path.contains("/AppTranslocation/") {
            state = .failed("Move Cape to your Applications folder, open it from there, then update.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            state = .failed("Cape can't write to \(appURL.deletingLastPathComponent().path).")
            return
        }
        guard let requirement = Self.ownRequirement() else {
            state = .failed("This copy of Cape isn't signed with the release key (a local ad-hoc build), so it can't verify updates. Download the new version manually.")
            return
        }

        state = .downloading(0)
        Task { [weak self] in
            guard let self else { return }
            do {
                let zip = try await self.download(zipURL)
                await MainActor.run { self.state = .installing }
                let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                          appropriateFor: appURL, create: true)
                defer { try? FileManager.default.removeItem(at: staging); try? FileManager.default.removeItem(at: zip) }
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])

                let newApp = staging.appendingPathComponent("Cape.app")
                try Self.verify(newApp, version: release.version, requirement: requirement)
                try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

                _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp)
                // Relaunching ends this process, so the `defer` above never runs on
                // success — clean up the download and staging folder first.
                try? FileManager.default.removeItem(at: staging)
                try? FileManager.default.removeItem(at: zip)
                await MainActor.run { Self.relaunch(appURL) }
            } catch {
                await MainActor.run { self.state = .failed(Self.message(error)) }
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                if let error { cont.resume(throwing: error); return }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    cont.resume(throwing: UpdateError("The download failed.")); return
                }
                // The temp file is deleted once this handler returns — keep it.
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Cape-update-\(UUID().uuidString).zip")
                do { try FileManager.default.moveItem(at: tmp, to: dest); cont.resume(returning: dest) }
                catch { cont.resume(throwing: error) }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                DispatchQueue.main.async {
                    if case .downloading = self?.state { self?.state = .downloading(p.fractionCompleted) }
                }
            }
            task.resume()
        }
    }

    /// The new bundle must be Cape, the advertised version, and sealed by the
    /// same certificate as the running app (its designated requirement).
    private static func verify(_ app: URL, version: String, requirement: SecRequirement) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "io.cape.app" else {
            throw UpdateError("The download isn't Cape.")
        }
        let got = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        guard got == version else { throw UpdateError("Version mismatch in the download (\(got)).") }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckNestedCode), requirement) == errSecSuccess
        else { throw UpdateError("The update's signature doesn't match — not installed.") }
    }

    /// Our own designated requirement ("io.cape.app, sealed by certificate X") —
    /// nil for an ad-hoc build, whose requirement is just its own hash.
    private static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let certs = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [Any],
              !certs.isEmpty,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    /// Wait for this process to exit, then open the (new) app.
    private static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? sh.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError("\((path as NSString).lastPathComponent) failed (\(p.terminationStatus)).")
        }
        return p.terminationStatus
    }

    private static func message(_ error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}

struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
