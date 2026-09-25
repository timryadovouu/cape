import AppKit
import Darwin
import SwiftUI

/// "Ports": what's listening on this Mac's TCP ports — the dev server on
/// :3000, a forgotten Vite on :5173 — with its project folder and uptime, a
/// click to open it in the browser, and one to stop it. Read with `lsof` (your
/// own processes, no permission needed); polled only while the page is open.
final class PortsMonitor: ObservableObject {
    struct Listener: Identifiable, Equatable {
        var id: String { "\(pid):\(port)" }
        let port: Int
        let pid: pid_t
        let name: String          // "node", "Python", "Docker"
        let project: String?      // working-directory folder, e.g. "my-app"
        let started: Date?
        let exposed: Bool         // bound to all interfaces (reachable from the LAN)
        let isDev: Bool           // a dev tool, not a system service / regular app
    }

    @Published private(set) var listeners: [Listener] = []
    @Published private(set) var loaded = false

    private var timer: Timer?
    private var users = 0
    private let queue = DispatchQueue(label: "io.cape.ports")

    /// Start polling (every few seconds) while someone is looking.
    func start() {
        users += 1
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Screenshot tool: show these, never scan.
    func showDemo(_ demo: [Listener]) {
        demoMode = true
        listeners = demo
        loaded = true
    }
    private var demoMode = false

    func refresh() {
        guard !demoMode else { return }
        queue.async { [weak self] in
            let found = Self.scan()
            DispatchQueue.main.async {
                if self?.listeners != found { self?.listeners = found }
                self?.loaded = true
            }
        }
    }

    /// SIGTERM, then SIGKILL if it's still around after 2 s.
    func kill(_ listener: Listener) {
        let pid = listener.pid
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
            self?.refresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func open(_ listener: Listener) {
        if let url = URL(string: "http://localhost:\(listener.port)") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Scanning

    private static func scan() -> [Listener] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        // -F output: "p<pid>" starts a process, "n<addr>:<port>" per socket.
        var ports: [pid_t: [Int: Bool]] = [:]      // pid → port → exposed
        var pid: pid_t = 0
        for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            if tag == "p" { pid = pid_t(value) ?? 0 }
            else if tag == "n", pid > 0, let colon = value.lastIndex(of: ":"),
                    let port = Int(value[value.index(after: colon)...]) {
                let host = value[..<colon]
                let exposed = host == "*" || host == "0.0.0.0" || host == "[::]"
                ports[pid, default: [:]][port] = (ports[pid]?[port] ?? false) || exposed
            }
        }

        var result: [Listener] = []
        for (pid, byPort) in ports {
            let exe = executablePath(pid)
            let name = displayName(exe)
            let dev = isDevTool(name: name, path: exe)
            let project = workingDirectory(pid).flatMap(projectName)
            let started = startTime(pid)
            for (port, exposed) in byPort {
                result.append(Listener(port: port, pid: pid, name: name, project: project,
                                       started: started, exposed: exposed, isDev: dev))
            }
        }
        return result.sorted { $0.port < $1.port }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    private static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) }
        }
    }

    private static func startTime(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// The app's name for something inside an .app bundle, else the binary's name.
    private static func displayName(_ path: String?) -> String {
        guard let path else { return "?" }
        let parts = path.split(separator: "/")
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return parts.last.map(String.init) ?? path
    }

    /// The folder the server was started in — unless that's just / or ~.
    private static func projectName(_ cwd: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !cwd.isEmpty, cwd != "/", cwd != home else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    private static let devNames: Set<String> = [
        "node", "bun", "deno", "python", "python3", "Python", "ruby", "java", "go", "php", "perl",
        "dotnet", "beam.smp", "erl", "elixir", "postgres", "mysqld", "mongod", "redis-server",
        "nginx", "httpd", "caddy", "Docker", "com.docker.backend", "vpnkit", "ollama", "esbuild",
    ]

    /// Dev servers vs. the system's and regular apps' own listeners (AirPlay,
    /// Spotify, VS Code helpers…), which stay behind "Show all".
    private static func isDevTool(name: String, path: String?) -> Bool {
        if devNames.contains(name) || name.hasPrefix("python") { return true }
        guard let path else { return false }
        let system = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/Library/Apple/", "/Applications/"]
        return !system.contains { path.hasPrefix($0) } && !path.contains(".app/")
    }
}

// MARK: - The Ports page (inside Tools)

struct PortsPage: View {
    @ObservedObject var ports: PortsMonitor
    let onBack: () -> Void
    @State private var showAll = false
    @State private var confirmKill: String?     // listener id awaiting the second click

    private var shown: [PortsMonitor.Listener] {
        showAll ? ports.listeners : ports.listeners.filter(\.isDev)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("Tools").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("Ports").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { showAll.toggle() } label: {
                    HStack(spacing: 6) {
                        Text("Show all").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        CoralSwitch(isOn: showAll)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Also show system services and apps (AirPlay, Spotify…)")
            }

            if !ports.loaded {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if shown.isEmpty {
                Spacer()
                Text(showAll ? "Nothing is listening" : "No dev servers running")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(shown) { row($0) }
                    }
                }
            }
        }
        .onAppear { ports.start() }
        .onDisappear { ports.stop() }
    }

    private func row(_ l: PortsMonitor.Listener) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(l.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(l.isDev ? Color.coral : .white.opacity(0.6))
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(l.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if let project = l.project {
                        Text(project).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    Text(verbatim: "pid \(l.pid)")
                    if let started = l.started { Text("· up \(uptime(started))") }
                    if l.exposed {
                        Label("LAN", systemImage: "network").labelStyle(.titleAndIcon)
                            .help("Listens on all interfaces — reachable from your network")
                    }
                }
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 4)
            iconButton("safari", help: "Open localhost:\(l.port)") { ports.open(l) }
            if confirmKill == l.id {
                Button { confirmKill = nil; ports.kill(l) } label: {
                    Text("Stop?")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 44, height: 26)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.red.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .help("Click again to stop \(l.name) (pid \(l.pid))")
            } else {
                iconButton("xmark", help: "Stop this process", danger: true) {
                    confirmKill = l.id
                    // The confirmation quietly resets if not clicked.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if confirmKill == l.id { confirmKill = nil }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconButton(_ icon: String, help: String, danger: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(danger ? Color(red: 1, green: 0.5, blue: 0.5) : .white.opacity(0.75))
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(danger ? Color.red.opacity(0.18) : Color.white.opacity(0.13)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func uptime(_ since: Date) -> String {
        let s = Int(Date().timeIntervalSince(since))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86_400)d"
    }
}

/// The Tools-page entry for Ports: a full-width bar with the dev ports in use.
struct PortsBar: View {
    @ObservedObject var ports: PortsMonitor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let dev = ports.listeners.filter(\.isDev)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.coral)
                    .frame(width: 26, height: 26)
                    .background(Color.coral.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Ports").font(.system(size: 12, weight: .semibold))
                Text(summary(dev))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(hovering ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onAppear { ports.start() }
        .onDisappear { ports.stop() }
    }

    private func summary(_ dev: [PortsMonitor.Listener]) -> String {
        guard ports.loaded else { return "" }
        if dev.isEmpty { return "no dev servers" }
        let list = dev.prefix(4).map { ":\($0.port) \($0.project ?? $0.name)" }.joined(separator: " · ")
        return dev.count > 4 ? list + " +\(dev.count - 4)" : list
    }
}
