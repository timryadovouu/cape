import AppKit
import Carbon
import SwiftUI

/// One-shot utilities — not tabs. They live on the Tools page (the grid button
/// in the rail) and can each get a global shortcut in Settings › Tools.
enum Tool: String, CaseIterable, Identifiable {
    case colorPicker, cleanKeyboard
    var id: String { rawValue }

    var name: String {
        switch self {
        case .colorPicker: return "Pick color"
        case .cleanKeyboard: return "Clean keyboard"
        }
    }
    var detail: String {
        switch self {
        case .colorPicker: return "Copies the hex to the buffer"
        case .cleanKeyboard: return "Locks keys while you wipe it"
        }
    }
    var icon: String {
        switch self {
        case .colorPicker: return "eyedropper"
        case .cleanKeyboard: return "keyboard"
        }
    }
    /// Stable id for the global hotkey registration.
    var hotkeyID: UInt32 {
        switch self {
        case .colorPicker: return 1
        case .cleanKeyboard: return 2
        }
    }
}

extension AppModules {
    /// Run a tool — from its tile or its global shortcut.
    func run(_ tool: Tool, state: NotchState) {
        switch tool {
        case .colorPicker:
            EyeDropper.pick { hex, color in state.flashColor(hex, Color(nsColor: color)) }
        case .cleanKeyboard:
            keyboardCleaner.start()
        }
    }
}

// MARK: - Shortcut

/// A recorded key combination (at least one of ⌘ ⌥ ⌃, optionally ⇧).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt          // NSEvent.ModifierFlags raw value
    var key: String              // display name of the key, e.g. "C", "Space", "F5"

    var display: String {
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Key name as printed on the keycap (ASCII layout, so a Russian layout still
    /// shows "C", not "С").
    static func keyName(_ keyCode: UInt16) -> String {
        let special: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let s = special[keyCode] { return s }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Global hotkeys

/// System-wide shortcuts via Carbon `RegisterEventHotKey` — no Accessibility
/// permission needed (unlike watching bare modifiers such as double-⌥).
final class GlobalHotkeys: ObservableObject {
    static let shared = GlobalHotkeys()

    /// Ids whose combination is already taken (by another app or another tool).
    @Published private(set) var failed: Set<UInt32> = []

    private var entries: [UInt32: (shortcut: Shortcut, action: () -> Void)] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var paused = false
    private static let signature: OSType = 0x4341_5045   // 'CAPE'

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotkey = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            if err == noErr {
                let id = hotkey.id
                DispatchQueue.main.async { GlobalHotkeys.shared.entries[id]?.action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(id: UInt32, _ shortcut: Shortcut, action: @escaping () -> Void) {
        unregister(id: id)
        entries[id] = (shortcut, action)
        if !paused { install(id) }
    }

    func unregister(id: UInt32) {
        uninstall(id)
        entries[id] = nil
        failed.remove(id)
    }

    /// While a shortcut is being recorded, stand down so the combo reaches the
    /// recorder instead of firing a tool.
    func setPaused(_ on: Bool) {
        guard on != paused else { return }
        paused = on
        if on { refs.keys.forEach(uninstall) } else { entries.keys.sorted().forEach(install) }
    }

    private func install(_ id: UInt32) {
        guard let entry = entries[id] else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(entry.shortcut.keyCode), entry.shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            failed.remove(id)
        } else {
            failed.insert(id)
        }
    }

    private func uninstall(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}

// MARK: - Settings: shortcut recorder

/// "Record Shortcut" button: click, press a combination (with ⌘, ⌥ or ⌃).
/// Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let hotkeyID: UInt32
    @ObservedObject private var hotkeys = GlobalHotkeys.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Button { recording ? stop() : start() } label: {
                    Text(recording ? "Type shortcut…" : shortcut?.display ?? "Record Shortcut")
                        .monospacedDigit()
                        .frame(minWidth: 110)
                }
                if shortcut != nil, !recording {
                    Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove the shortcut")
                }
            }
            if hotkeys.failed.contains(hotkeyID), !recording {
                Text("Already used by another app or tool")
                    .font(.caption2).foregroundStyle(.red)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        GlobalHotkeys.shared.setPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stop(); return nil }                     // Esc — cancel
            if mods.isEmpty, event.keyCode == 51 || event.keyCode == 117 {    // ⌫ — clear
                shortcut = nil; stop(); return nil
            }
            guard !mods.isDisjoint(with: [.command, .option, .control]) else {
                NSSound.beep(); return nil                                    // needs ⌘/⌥/⌃
            }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue,
                                key: Shortcut.keyName(event.keyCode))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalHotkeys.shared.setPaused(false)
    }
}

// MARK: - Tools page (in the notch)

struct ToolsPanel: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: NotchState
    let modules: AppModules

    var body: some View {
        if state.showingPorts {
            PortsPage(ports: modules.ports) { state.showingPorts = false }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                tile(.colorPicker)
                tile(.cleanKeyboard)
                ToggleTile(name: "Reverse wheel", detail: "Mouse only, trackpad stays",
                           icon: "computermouse", isOn: $settings.reverseMouseScroll)
                ToggleTile(name: "QR in images", detail: "Adds links from screenshots",
                           icon: "qrcode.viewfinder", isOn: $settings.scanQRInImages)
            }
            PortsBar(ports: modules.ports) { state.showingPorts = true }
            Spacer(minLength: 0)
            Button { modules.settingsWindow.show(.tools) } label: {
                Text("Set a shortcut for any tool in Settings › Tools")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private func tile(_ tool: Tool) -> some View {
        ToolTile(tool: tool, shortcut: settings.toolShortcuts[tool.rawValue]) {
            modules.run(tool, state: state)
        }
    }
}

/// A tool that stays on (a switch, not a one-shot) — same size as a ToolTile.
private struct ToggleTile: View {
    let name: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOn ? Color.coral : .white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background((isOn ? Color.coral : .white).opacity(isOn ? 0.14 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CoralSwitch(isOn: isOn)
            }
            .padding(8)
            .background(Color.white.opacity(hovering ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ToolTile: View {
    let tool: Tool
    let shortcut: Shortcut?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.coral)
                    .frame(width: 34, height: 34)
                    .background(Color.coral.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.system(size: 12, weight: .semibold))
                    Text(tool.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut.display)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(8)
            .background(Color.white.opacity(hovering ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
