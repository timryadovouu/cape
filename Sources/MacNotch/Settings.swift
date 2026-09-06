import Foundation
import Combine
import ServiceManagement

/// Persisted app settings (UserDefaults-backed).
final class Settings: ObservableObject {
    // MARK: Buffer
    @Published var bufferRootPath: String { didSet { d.set(bufferRootPath, forKey: "bufferRootPath") } }
    @Published var bufferRetentionDays: Int { didSet { d.set(bufferRetentionDays, forKey: "bufferRetentionDays") } }
    @Published var clearBufferAtEndOfDay: Bool { didSet { d.set(clearBufferAtEndOfDay, forKey: "clearBufferAtEndOfDay") } }

    // MARK: Notch
    @Published var recallMinutes: Int { didSet { d.set(recallMinutes, forKey: "recallMinutes") } }
    @Published var defaultModuleRaw: String { didSet { d.set(defaultModuleRaw, forKey: "defaultModuleRaw") } }

    // MARK: Modules (order + which are enabled)
    @Published var moduleOrder: [String] { didSet { d.set(moduleOrder, forKey: "moduleOrder") } }
    @Published var disabledModules: [String] { didSet { d.set(disabledModules, forKey: "disabledModules") } }

    // MARK: Timer
    @Published var shortBreakMinutes: Int { didSet { d.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { d.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var pomodoroSound: Bool { didSet { d.set(pomodoroSound, forKey: "pomodoroSound") } }
    @Published var pomodoroSoundName: String { didSet { d.set(pomodoroSoundName, forKey: "pomodoroSoundName") } }
    @Published var soundDuringDND: Bool { didSet { d.set(soundDuringDND, forKey: "soundDuringDND") } }

    // MARK: Screen Time
    @Published var screenTimeRetentionDays: Int { didSet { d.set(screenTimeRetentionDays, forKey: "screenTimeRetentionDays") } }

    // MARK: General
    @Published var launchAtLogin: Bool { didSet { applyLoginItem() } }
    @Published var trackClaude: Bool { didSet { d.set(trackClaude, forKey: "trackClaude") } }

    private let d = UserDefaults.standard

    init() {
        bufferRootPath = d.string(forKey: "bufferRootPath")
            ?? AppModules.supportDirectory.appendingPathComponent("localBuffer").path
        bufferRetentionDays = d.object(forKey: "bufferRetentionDays") as? Int ?? 7
        clearBufferAtEndOfDay = d.object(forKey: "clearBufferAtEndOfDay") as? Bool ?? false
        recallMinutes = d.object(forKey: "recallMinutes") as? Int ?? 30
        defaultModuleRaw = d.string(forKey: "defaultModuleRaw") ?? Module.tasks.rawValue

        // Normalize module order: keep known modules, append any new ones.
        var order = d.stringArray(forKey: "moduleOrder") ?? Module.allCases.map(\.rawValue)
        order = order.filter { Module(rawValue: $0) != nil }
        for m in Module.allCases where !order.contains(m.rawValue) { order.append(m.rawValue) }
        moduleOrder = order
        disabledModules = d.stringArray(forKey: "disabledModules") ?? []

        shortBreakMinutes = d.object(forKey: "shortBreakMinutes") as? Int ?? 5
        longBreakMinutes = d.object(forKey: "longBreakMinutes") as? Int ?? 15
        pomodoroSound = d.object(forKey: "pomodoroSound") as? Bool ?? true
        pomodoroSoundName = d.string(forKey: "pomodoroSoundName") ?? "Funk"
        soundDuringDND = d.object(forKey: "soundDuringDND") as? Bool ?? true

        screenTimeRetentionDays = d.object(forKey: "screenTimeRetentionDays") as? Int ?? 365

        trackClaude = d.object(forKey: "trackClaude") as? Bool ?? false
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Derived

    var bufferRoot: URL { URL(fileURLWithPath: bufferRootPath) }

    var orderedModules: [Module] { moduleOrder.compactMap { Module(rawValue: $0) } }
    func isEnabled(_ m: Module) -> Bool { !disabledModules.contains(m.rawValue) }
    var enabledModules: [Module] { orderedModules.filter(isEnabled) }

    var defaultModule: Module {
        let m = Module(rawValue: defaultModuleRaw) ?? .tasks
        return isEnabled(m) ? m : (enabledModules.first ?? .tasks)
    }

    // MARK: - Module editing

    func moveModule(_ m: Module, up: Bool) {
        guard let i = moduleOrder.firstIndex(of: m.rawValue) else { return }
        let j = up ? i - 1 : i + 1
        guard moduleOrder.indices.contains(j) else { return }
        moduleOrder.swapAt(i, j)
    }

    func setModuleEnabled(_ m: Module, _ on: Bool) {
        if on {
            disabledModules.removeAll { $0 == m.rawValue }
        } else if !disabledModules.contains(m.rawValue) {
            // Never allow disabling the very last enabled module.
            guard enabledModules.count > 1 else { return }
            disabledModules.append(m.rawValue)
        }
    }

    // MARK: - Login item

    private func applyLoginItem() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Ignore (e.g. running via `swift run` without a bundle).
        }
    }
}
