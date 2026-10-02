import AppKit
import Darwin
import IOKit
import IOKit.pwr_mgt

/// How much battery each app used — the day's energy per app, beside Screen
/// Time's minutes. Adds up to what the battery really lost.
///
/// Two parts, once a minute:
/// - **The app's own work.** macOS keeps an energy counter per process
///   (`ri_energy_nj`, nanojoules), readable for your own processes with
///   `proc_pid_rusage`. Cape takes each one's difference since the last reading
///   and adds it to the process's app (helpers inside an .app count for that
///   app; macOS's own agents are "macOS").
/// - **The screen and the rest of the Mac.** That's most of it — the backlight,
///   the chip's baseline, Wi-Fi, WindowServer, system processes Cape can't read,
///   short-lived ones (compilers) gone between readings. Cape measures the
///   whole Mac (the battery's charge going down; the system's power meter on
///   the charger), takes away what the apps did themselves, and gives the rest
///   to the app on screen in that minute — as the iPhone does. Time away (no
///   input for two minutes, the display asleep, the Mac asleep) goes to "macOS";
///   a video playing isn't time away.
///
/// Two sums per app: everything, and only while on battery — Settings › Screen
/// Time picks which one is shown. Shown as a share of a full charge. About a
/// millisecond of CPU a minute; a small file per day. Runs only while the
/// Screen Time tab is on.
final class EnergyMonitor: ObservableObject {
    struct AppEnergy: Codable, Equatable {
        var name: String
        var all: Double = 0             // joules: its own work + its share of the screen and system
        var battery: Double = 0         // the same, only while on battery
        var screenAll: Double = 0       // of `all`: the screen and system, while it was in front
        var screenBattery: Double = 0   // of `battery`: the same
    }

    /// Today's energy by app key (the .app bundle path, "macOS", or a tool's path).
    @Published private(set) var today: [String: AppEnergy] = [:]

    static let systemKey = "macOS"
    /// A full charge in joules (nil on a Mac without a battery) — today's, worn
    /// battery's; read again every hour, as it keeps shrinking with age.
    private(set) static var capacity: Double? = batteryCapacity()
    private var capacityRead = Date()

    private let settings: Settings
    private var day = AppUsageTracker.dayString(Date())
    /// The last reading per process — with its start time, so a pid macOS has
    /// reused for a new process isn't mistaken for the old one.
    private var last: [pid_t: (counter: UInt64, key: String, started: Date?)] = [:]
    private var lastSample = Date()
    /// The whole Mac at the last reading: the battery's charge (mAh) and the
    /// system's energy meter (joules).
    private var lastMeter: Meter?
    private var overshoot = 0.0
    private var names: [String: String] = [:]          // key → display name (cached)
    private var timer: Timer?
    private let queue = DispatchQueue(label: "io.cape.energy", qos: .utility)

    // On the main thread: which app is in front, and for how long this minute.
    private var front: (key: String, since: Date)?
    private var onScreen: [String: TimeInterval] = [:]
    private var activation: NSObjectProtocol?

    private let live: Bool

    init(settings: Settings, live: Bool = true) {
        self.settings = settings
        self.live = live
        guard live else { return }
        today = Self.load(day)
        cleanupOld()
    }

    deinit {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
    }

    /// Measure only while the Screen Time tab is on (Settings › Tabs). Off:
    /// no timer, no app-switch observer, nothing recorded. Back on, the first
    /// reading is only a starting point — the time it was off isn't counted.
    func setActive(_ on: Bool) {
        guard live, on != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        front = nil
        onScreen = [:]
        guard on else { return }
        front = Self.frontKey(NSWorkspace.shared.frontmostApplication).map { ($0, Date()) }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.creditFront(Date())
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.front = Self.frontKey(app).map { ($0, Date()) }
        }
        queue.async { [weak self] in                                   // the baseline
            guard let self else { return }
            self.last = [:]
            self.lastMeter = nil
            self.overshoot = 0
            self.lastSample = Date()
            self.sample(onScreen: [:], idle: 0)
        }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The day's energy for the counter Settings picks (on battery / always).
    func joules(_ e: AppEnergy) -> Double { settings.energyOnBatteryOnly ? e.battery : e.all }
    /// Of that, the screen and system's share while the app was in front.
    func screenJoules(_ e: AppEnergy) -> Double { settings.energyOnBatteryOnly ? e.screenBattery : e.screenAll }

    /// The energy of the day `offset` days from today (0 = today).
    func day(offset: Int) -> [String: AppEnergy] {
        offset == 0 ? today : Self.load(AppUsageTracker.dayString(Self.date(offset)))
    }

    /// Screenshot tool: show these, never measure.
    func showDemo(_ demo: [String: AppEnergy]) { today = demo }

    // MARK: - Who's on screen (main thread)

    private func creditFront(_ now: Date) {
        guard let f = front else { return }
        onScreen[f.key, default: 0] += now.timeIntervalSince(f.since)
        front = (f.key, now)
    }

    /// The app's key, as its processes get it (nil for the lock screen / screensaver).
    private static func frontKey(_ app: NSRunningApplication?) -> String? {
        guard let app, !["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]
            .contains(app.bundleIdentifier ?? "") else { return nil }
        return key(for: app.processIdentifier)
    }

    private func tick() {
        let now = Date()
        creditFront(now)
        let share = onScreen
        onScreen = [:]
        let idle = Self.awaySeconds()
        queue.async { [weak self] in self?.sample(onScreen: share, idle: idle) }
    }

    /// How long you've been away: seconds since the last key / mouse / trackpad
    /// input; 0 while something keeps the display awake (a video); forever
    /// while the display sleeps.
    private static func awaySeconds() -> TimeInterval {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return .infinity }
        var status: Unmanaged<CFDictionary>?
        if IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
           let dict = status?.takeRetainedValue() as? [String: Any],
           (dict["PreventUserIdleDisplaySleep"] as? Int ?? 0) > 0 {
            return 0
        }
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // MARK: - Sampling (background queue)

    private func sample(onScreen: [String: TimeInterval], idle: TimeInterval) {
        let now = Date()
        let onBattery = !PowerMonitor.isOnAC()
        var own: [String: Double] = [:]
        var seen: [pid_t: (counter: UInt64, key: String, started: Date?)] = [:]

        for pid in Self.allPIDs() {
            guard let counter = Self.energy(pid) else { continue }
            let started = Self.startTime(pid)
            let prev = last[pid].flatMap { $0.started == started ? $0 : nil }   // same process as before?
            let key = prev?.key ?? Self.key(for: pid)
            seen[pid] = (counter, key, started)
            if let prev {
                if counter >= prev.counter { own[key, default: 0] += Double(counter - prev.counter) / 1e9 }
            } else if let started, started > lastSample {
                own[key, default: 0] += Double(counter) / 1e9        // born since the last reading
            }                                                          // else: first sight — the baseline
        }

        // The whole Mac since the last reading, and what's left beyond the apps' own work.
        let interval = now.timeIntervalSince(lastSample)
        let meter = Self.meter()
        var whole = lastMeter.flatMap { Self.used(from: $0, to: meter, onBattery: onBattery) }
        if let prev = lastMeter, interval < 150 {
            whole = whole.map { $0 * calibrate(from: prev, to: meter, meterJoules: $0, onBattery: onBattery) }
        }
        lastMeter = meter
        last = seen
        lastSample = now
        // The meter updates about once a minute too, so a minute can read nothing
        // and the next one two minutes' worth: what the apps' own work overshot is
        // carried over, so the sums keep matching the whole Mac.
        var rest = 0.0
        if let whole {
            rest = whole - own.values.reduce(0, +) - overshoot
            overshoot = max(0, -rest)
            rest = max(0, rest)
        }

        // The rest goes to the apps on screen, by their time in front — except the
        // time you were away (and a Mac that slept through the minute), which is macOS's.
        var screen: [String: Double] = [:]
        if rest > 0 {
            let inFront = onScreen.values.reduce(0, +)
            let present = interval > 150 ? 0 : max(0, min(1, (interval - max(0, idle - 120)) / interval))
            var given = 0.0
            if inFront > 0 && present > 0 {
                for (key, seconds) in onScreen where seconds > 0 {
                    let share = seconds / inFront * present
                    screen[key, default: 0] += rest * share
                    given += share
                }
            }
            if given < 1 { screen[Self.systemKey, default: 0] += rest * (1 - given) }
        }

        let keys = Set(own.keys).union(screen.keys).filter { names[$0] == nil }
        for key in keys { names[key] = Self.displayName(key) }
        let labels = names

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stamp = AppUsageTracker.dayString(now)
            if now.timeIntervalSince(self.capacityRead) > 3600 {
                self.capacityRead = now
                Self.capacity = Self.batteryCapacity() ?? Self.capacity
            }
            if stamp != self.day {                                     // a new day
                self.save()
                self.day = stamp
                self.today = [:]
            }
            var totals = self.today
            for key in Set(own.keys).union(screen.keys) {
                let mine = own[key] ?? 0, shown = screen[key] ?? 0
                guard mine + shown > 0 else { continue }
                var e = totals[key] ?? AppEnergy(name: labels[key] ?? key)
                e.all += mine + shown
                e.screenAll += shown
                if onBattery {
                    e.battery += mine + shown
                    e.screenBattery += shown
                }
                totals[key] = e
            }
            if totals != self.today { self.today = totals; self.save() }
        }
    }

    // MARK: - The whole Mac

    /// On battery the meter is scaled to what the charge really lost, so the
    /// figures add up to the menu bar's percent: both are summed over the
    /// recent hours of battery time (the charge moves in steps; over hours it's
    /// exact) and their ratio, within reason, applied. Kept across launches.
    private func calibrate(from a: Meter, to b: Meter, meterJoules: Double, onBattery: Bool) -> Double {
        let d = UserDefaults.standard
        var charge = d.double(forKey: "energyCalCharge"), metered = d.double(forKey: "energyCalMeter")
        if onBattery, a.system != nil, let c0 = a.charge, let c1 = b.charge, c1 <= c0 {
            charge += (c0 - c1) * Self.nominalVolts * 3.6
            metered += meterJoules
            if metered > 200_000 { charge /= 2; metered /= 2 }       // keep it recent
            d.set(charge, forKey: "energyCalCharge")
            d.set(metered, forKey: "energyCalMeter")
        }
        guard onBattery, metered > 20_000 else { return 1 }          // not enough to tell yet
        return min(1.6, max(0.7, charge / metered))
    }

    struct Meter {
        var charge: Double?                         // the battery's charge, mAh
        var system: (load: Double, count: Double)?  // the system's power meter: mW summed, samples
    }

    /// Joules the Mac used between two readings. The system's power meter first
    /// (Apple silicon: a reading of the whole Mac's draw every second, on battery
    /// and on the charger — smooth, where the charge moves in steps); else, on
    /// battery, the charge that went.
    private static func used(from a: Meter, to b: Meter, onBattery: Bool) -> Double? {
        if let s0 = a.system, let s1 = b.system, s1.count >= s0.count, s1.load >= s0.load {
            return (s1.load - s0.load) / 1000 * secondsPerSample
        }
        if onBattery, let c0 = a.charge, let c1 = b.charge, c1 <= c0 {
            return (c0 - c1) * nominalVolts * 3.6
        }
        return nil
    }

    /// The power meter's sampling period (measured: ~0.94 samples a second).
    private static let secondsPerSample = 1.065

    private static func meter() -> Meter {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return Meter() }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let telemetry = property("PowerTelemetryData") as? [String: Any]
        let load = (telemetry?["AccumulatedSystemLoad"] as? NSNumber)?.doubleValue
        let count = (telemetry?["SystemLoadAccumulatorCount"] as? NSNumber)?.doubleValue
        return Meter(charge: (property("AppleRawCurrentCapacity") as? NSNumber)?.doubleValue,
                     system: load.flatMap { l in count.map { (l, $0) } })
    }

    // MARK: - Processes

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(0, n))).filter { $0 > 0 }
    }

    /// The process's energy counter in nanojoules (nil if not ours to read).
    private static func energy(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return ok == 0 ? info.ri_energy_nj : nil
    }

    private static func startTime(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// Which app a process belongs to: the outermost .app around its binary
    /// (Chrome's helpers → Google Chrome.app), macOS's own agents → "macOS",
    /// anything else (node, python…) → its own path.
    private static func key(for pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return systemKey }
        let path = String(cString: buf)
        if let range = path.range(of: ".app/") { return String(path[..<range.lowerBound]) + ".app" }
        let system = ["/System/", "/usr/", "/Library/Apple/", "/sbin/", "/bin/"]
        if system.contains(where: path.hasPrefix) { return systemKey }
        return path
    }

    /// The app's own name (its bundle's, not the folder's: Claude lives in "_.app").
    private static func displayName(_ key: String) -> String {
        if key == systemKey { return "macOS" }
        if key.hasSuffix(".app"), let bundle = Bundle(path: key) {
            let info = bundle.localizedInfoDictionary ?? [:]
            let base = bundle.infoDictionary ?? [:]
            if let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"]
                           ?? base["CFBundleDisplayName"] ?? base["CFBundleName"]) as? String, !name.isEmpty {
                return name
            }
        }
        return ((key as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    // MARK: - Battery

    /// What a full charge holds now, in joules. The charge is the gauge's own
    /// figure for today's battery (`AppleRawMaxCapacity` — wear included, the
    /// same 100% as the menu bar's), not the design capacity. Volts are the
    /// pack's nominal ones (3.84 V a cell): the live voltage swings from ~13 V
    /// full to ~9 V empty and would skew every percentage by up to ±15%.
    private static func batteryCapacity() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        func number(_ key: String) -> Double? { (property(key) as? NSNumber)?.doubleValue }
        guard let mAh = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"), mAh > 0 else { return nil }
        let cells = ((property("BatteryData") as? [String: Any])?["CellVoltage"] as? [Any])?.count ?? 0
        let volts = cells > 0 ? Double(cells) * 3.84 : (number("Voltage") ?? 0) / 1000
        guard volts > 0 else { return nil }
        nominalVolts = volts
        return mAh / 1000 * volts * 3600
    }

    /// The pack's nominal voltage (set with the capacity; 3 cells if unknown).
    private static var nominalVolts = 11.52

    /// "7%", "3.4%", "<0.1%" of a full charge — or watt-hours without a battery.
    static func label(_ joules: Double) -> String {
        guard let capacity else { return String(format: "%.1f Wh", joules / 3600) }
        let pct = joules / capacity * 100
        if pct < 0.1 { return "<" + number(0.1, digits: 1) + "%" }
        return number(pct, digits: pct < 10 ? 1 : 0) + "%"
    }

    /// One formatter per precision (the language is fixed for the launch).
    private static let formatters: [Int: NumberFormatter] = [0, 1].reduce(into: [:]) { out, digits in
        let f = NumberFormatter()
        f.locale = AppLanguage.locale
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        out[digits] = f
    }

    private static func number(_ value: Double, digits: Int) -> String {
        formatters[digits]?.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Storage (Application Support/Cape/energy/<day>.json)

    private static var dir: URL {
        let u = AppModules.supportDirectory.appendingPathComponent("energy", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private static func load(_ day: String) -> [String: AppEnergy] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(day).json")),
              let apps = try? JSONDecoder().decode([String: AppEnergy].self, from: data) else { return [:] }
        return apps
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(today) else { return }
        try? data.write(to: Self.dir.appendingPathComponent("\(day).json"), options: .atomic)
    }

    private func cleanupOld() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.screenTimeRetentionDays, to: Date())
            ?? .distantPast
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            if let d = AppUsageTracker.date(from: file.deletingPathExtension().lastPathComponent), d < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func date(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}

extension EnergyMonitor.AppEnergy {
    /// Days saved before the screen's share existed lack those fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        all = try c.decodeIfPresent(Double.self, forKey: .all) ?? 0
        battery = try c.decodeIfPresent(Double.self, forKey: .battery) ?? 0
        screenAll = try c.decodeIfPresent(Double.self, forKey: .screenAll) ?? 0
        screenBattery = try c.decodeIfPresent(Double.self, forKey: .screenBattery) ?? 0
    }
}
