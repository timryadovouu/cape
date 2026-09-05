import SwiftUI
import AppKit

/// Opens the settings as a normal, standalone window (not inside the notch).
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let buffer: BufferManager
    private let claude: ClaudeSessionsManager

    init(settings: Settings, buffer: BufferManager, claude: ClaudeSessionsManager) {
        self.settings = settings
        self.buffer = buffer
        self.claude = claude
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "mac-notch Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(
                rootView: SettingsView(settings: settings, buffer: buffer, claude: claude)
            )
            // Place it below the expanded notch so opening it from the notch
            // doesn't overlap the panel.
            if let screen = NSScreen.main {
                let f = screen.frame
                let x = f.midX - w.frame.width / 2
                let y = f.maxY - (NotchRootView.panelHeight + 40) - w.frame.height
                w.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                w.center()
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Open the settings window, or hide it if it's already showing.
    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            show()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let buffer: BufferManager
    let claude: ClaudeSessionsManager

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Track Claude Code sessions", isOn: $settings.trackClaude)
                    .onChange(of: settings.trackClaude) { on in if on { claude.installHooks() } }
                if settings.trackClaude {
                    Stepper(value: $settings.claudeLimitThreshold, in: 50...100, step: 5) {
                        Text("Show limit reset from \(settings.claudeLimitThreshold)% usage")
                    }
                }
            }

            Section("Modules") {
                ForEach(settings.orderedModules) { module in
                    moduleRow(module)
                }
            }

            Section("Timer") {
                Stepper(value: $settings.shortBreakMinutes, in: 1...60) {
                    Text("Short break: \(settings.shortBreakMinutes) min")
                }
                Stepper(value: $settings.longBreakMinutes, in: 1...60) {
                    Text("Long break: \(settings.longBreakMinutes) min")
                }
                Toggle("Play sound when a session ends", isOn: $settings.pomodoroSound)
                if settings.pomodoroSound {
                    SoundPicker(selection: $settings.pomodoroSoundName)
                    Toggle("Play sound during Do Not Disturb / Focus", isOn: $settings.soundDuringDND)
                }
            }

            Section("Screen Time") {
                Picker("Keep history", selection: $settings.screenTimeRetentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                    Text("Unlimited").tag(100_000)
                }
            }

            Section("Buffer") {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(settings.bufferRootPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)
                    Button("Change…", action: pickFolder)
                }
                Stepper(value: $settings.bufferRetentionDays, in: 1...90) {
                    Text("Clear buffer older than \(settings.bufferRetentionDays) days")
                }
                .onChange(of: settings.bufferRetentionDays) { _ in buffer.applySettings() }
                .disabled(settings.clearBufferAtEndOfDay)

                Toggle("Delete each day's buffer at end of day", isOn: $settings.clearBufferAtEndOfDay)
                    .onChange(of: settings.clearBufferAtEndOfDay) { _ in buffer.applySettings() }
            }

            Section("Notch") {
                Stepper(value: $settings.recallMinutes, in: 1...240, step: 5) {
                    Text("Reset to default tab after \(settings.recallMinutes) min")
                }
                Picker("Default tab", selection: $settings.defaultModuleRaw) {
                    ForEach(settings.enabledModules) { module in
                        Text(module.name).tag(module.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 440)
    }

    private func moduleRow(_ module: Module) -> some View {
        HStack(spacing: 8) {
            Image(systemName: module.icon).frame(width: 18)
            Text(module.name)
            Spacer()
            Button { settings.moveModule(module, up: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(settings.moduleOrder.first == module.rawValue)
            Button { settings.moveModule(module, up: false) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(settings.moduleOrder.last == module.rawValue)
            Toggle("", isOn: Binding(
                get: { settings.isEnabled(module) },
                set: { settings.setModuleEnabled(module, $0) }
            ))
            .labelsHidden()
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.bufferRoot
        if panel.runModal() == .OK, let url = panel.url {
            settings.bufferRootPath = url.path
            buffer.applySettings()
        }
    }
}

/// macOS-style sound chooser: a compact control showing the current sound; click
/// it to drop down the list, and only there does hovering preview a sound — so
/// scrolling the Settings form never makes noise.
struct SoundPicker: View {
    @Binding var selection: String
    @State private var open = false
    @State private var hovered: String?

    var body: some View {
        HStack {
            Text("Sound")
            Spacer()
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(selection)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .popover(isPresented: $open, arrowEdge: .bottom) { list }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(SystemSounds.available, id: \.self) { row($0) }
            }
            .padding(4)
        }
        .frame(width: 210, height: min(CGFloat(SystemSounds.available.count) * 27 + 8, 320))
    }

    private func row(_ name: String) -> some View {
        let selected = name == selection
        let hot = hovered == name
        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .opacity(selected ? 1 : 0)
                .frame(width: 12)
            Text(name).font(.system(size: 13))
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(hot ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
        .onHover { h in
            if h { hovered = name; SystemSounds.preview(name) }
            else if hovered == name { hovered = nil }
        }
        .onTapGesture { selection = name; open = false }
    }
}
