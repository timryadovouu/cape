import SwiftUI
import AppKit

/// Opens the settings as a normal, standalone window (not inside the notch).
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let buffer: BufferManager
    private let claude: ClaudeSessionsManager
    private let voice: VoiceDictation
    private let updater: Updater

    init(settings: Settings, buffer: BufferManager, claude: ClaudeSessionsManager, voice: VoiceDictation,
         updater: Updater) {
        self.settings = settings
        self.buffer = buffer
        self.claude = claude
        self.voice = voice
        self.updater = updater
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Cape Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(
                rootView: SettingsView(settings: settings, voice: voice, updater: updater, buffer: buffer, claude: claude)
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
    @ObservedObject var voice: VoiceDictation
    @ObservedObject var updater: Updater
    let buffer: BufferManager
    let claude: ClaudeSessionsManager

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Track Claude Code sessions", isOn: $settings.trackClaude)
                    .onChange(of: settings.trackClaude) { on in if on { claude.installHooks() } }
            }

            Section("Updates") {
                UpdatesSection(updater: updater, settings: settings)
            }

            Section("Claude") {
                Toggle("Play a sound when Claude finishes", isOn: $settings.claudeSound)
                    .disabled(!settings.trackClaude)
                if settings.claudeSound {
                    SoundPicker(selection: $settings.claudeSoundName)
                    if settings.pomodoroSound && settings.pomodoroSoundName == settings.claudeSoundName {
                        Text("Same as the Pomodoro sound — pick another to tell them apart.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Toggle("Play during Do Not Disturb / Focus", isOn: $settings.claudeSoundDuringDND)
                    Toggle("Mute when the Claude app is in front", isOn: $settings.claudeSoundMuteWhenFront)
                }
                if !settings.trackClaude {
                    Text("Turn on “Track Claude Code sessions” above to use this.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    if settings.claudeSound && settings.pomodoroSoundName == settings.claudeSoundName {
                        Text("Same as the Claude finish sound — pick another to tell them apart.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Toggle("Play sound during Do Not Disturb / Focus", isOn: $settings.soundDuringDND)
                }
            }

            Section("Tools") {
                ForEach(Tool.allCases) { tool in
                    HStack {
                        Label(tool.name, systemImage: tool.icon)
                        Spacer()
                        ShortcutRecorder(shortcut: Binding(
                            get: { settings.toolShortcuts[tool.rawValue] },
                            set: { settings.toolShortcuts[tool.rawValue] = $0 }
                        ), hotkeyID: tool.hotkeyID)
                    }
                }
                Text("Global shortcuts need ⌘, ⌥ or ⌃. While recording, Esc cancels and ⌫ clears. No extra permissions needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tasks") {
                Toggle("Play a sound for reminders", isOn: $settings.reminderSound)
                if settings.reminderSound {
                    SoundPicker(selection: $settings.reminderSoundName)
                }
                Text("Add a time right in the task: “позвонить в 15:00”, “через 20 минут”, “завтра в 9”, “call mom at 3pm”. It rings beside the notch when due.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Voice") {
                Picker("Dictation model", selection: $settings.voiceModel) {
                    ForEach(VoiceModels.options, id: \.id) {
                        Text($0.label + (Transcriber.isModelDownloaded($0.id) ? "  ✓" : "")).tag($0.id)
                    }
                }
                Picker("Language", selection: $settings.voiceLanguage) {
                    ForEach(VoiceModels.languages, id: \.id) { Text($0.label).tag($0.id) }
                }
                Toggle("Translate to English", isOn: $settings.voiceTranslate)
                Toggle("Double-tap shortcut (start / stop)", isOn: $settings.voiceHotkey)
                    .onChange(of: settings.voiceHotkey) { _ in voice.applyHotkey() }
                if settings.voiceHotkey {
                    Picker("Shortcut", selection: $settings.voiceHotkeyTrigger) {
                        ForEach(VoiceHotkeyTrigger.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: settings.voiceHotkeyTrigger) { _ in voice.updateHotkeyTrigger() }
                }
                Toggle("Hold 🌐 Fn to talk", isOn: $settings.voiceHoldFn)
                    .onChange(of: settings.voiceHoldFn) { _ in voice.applyHotkey() }
                Toggle("Hold right ⌥ Option to talk", isOn: $settings.voiceHoldRightOption)
                    .onChange(of: settings.voiceHoldRightOption) { _ in voice.applyHotkey() }
                if settings.voiceHoldFn || settings.voiceHoldRightOption {
                    Text("Hold the key to record, release to transcribe. A quick press keeps working as usual. If the emoji picker pops up when you let go of 🌐, set System Settings › Keyboard › “Press 🌐 key to” › Do Nothing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Preload model at launch (faster first dictation)", isOn: $settings.voicePreload)

                if voice.status == .downloading {
                    HStack(spacing: 10) {
                        ProgressView(value: voice.downloadProgress)
                        Text("\(Int(voice.downloadProgress * 100))%")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else if Transcriber.isModelDownloaded(settings.voiceModel) {
                    HStack {
                        Label("Model downloaded", systemImage: "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(.green)
                        Spacer()
                        Button(role: .destructive) { confirmDeleteModel() } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this model from disk (re-download any time)")
                    }
                } else {
                    Button("Download model now") { voice.prepareModel() }
                }

                Text("Model is downloaded once (bigger = more accurate, more RAM). Auto-detect can misread some languages (e.g. Russian) — pick it explicitly if needed. A transcript starting with “заметка”/“note” goes to the Tasks list. The global shortcut needs Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Picker("Apps shown", selection: $settings.screenTimeAppCount) {
                    Text("Top 5").tag(5)
                    Text("Top 8").tag(8)
                    Text("Top 10").tag(10)
                    Text("Top 15").tag(15)
                    Text("Top 20").tag(20)
                    Text("All").tag(100_000)
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
                Toggle("Open Media when hovering the music island", isOn: $settings.openMediaOnHover)
                Toggle("Show battery level when the charger connects", isOn: $settings.showCharging)
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

    private func confirmDeleteModel() {
        let alert = NSAlert()
        alert.messageText = "Delete the dictation model?"
        alert.informativeText = "It will be removed from disk. You can re-download it any time from here."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { voice.deleteModel() }
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

/// Sound chooser mirroring macOS System Settings › Sound: a native menu picker
/// plus a ▶ button that previews the selected sound (no hover needed).
struct SoundPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            Text("Sound")
            Spacer()
            Picker("", selection: $selection) {
                ForEach(SystemSounds.available, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Button { SystemSounds.preview(selection) } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preview this sound")
        }
    }
}

/// Version, "Check for Updates", and the install flow for a found release.
private struct UpdatesSection: View {
    @ObservedObject var updater: Updater
    @ObservedObject var settings: Settings

    var body: some View {
        HStack {
            Text("Cape \(updater.currentVersion)")
            Spacer()
            Button("Check for Updates") { updater.check() }
                .disabled(updater.isBusy)
        }
        status
        Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Label("Cape \(release.version) is available", systemImage: "arrow.down.circle.fill")
                    .font(.headline).foregroundStyle(Color.coral)
                if !release.notes.isEmpty {
                    Text(release.notes)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(8)
                }
                HStack {
                    Button("Release notes") { NSWorkspace.shared.open(release.page) }
                    Spacer()
                    Button("Install & Relaunch") { updater.install(release) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.coral)
                }
            }
        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing — Cape will relaunch…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
