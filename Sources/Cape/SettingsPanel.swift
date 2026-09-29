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
    private let shell: ShellIntegration

    init(settings: Settings, buffer: BufferManager, claude: ClaudeSessionsManager, voice: VoiceDictation,
         updater: Updater, shell: ShellIntegration) {
        self.settings = settings
        self.buffer = buffer
        self.claude = claude
        self.voice = voice
        self.updater = updater
        self.shell = shell
    }

    /// Which page the sidebar shows — kept across launches.
    let navigation = SettingsNavigation()

    /// Open the window — on `page` if given, else where it was left.
    func show(_ page: SettingsPage? = nil) {
        if let page { navigation.page = page }
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = String(localized: "Cape Settings")
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsView(settings: settings, voice: voice, updater: updater, buffer: buffer,
                                       claude: claude, shell: shell, navigation: navigation)
            )
            w.setContentSize(NSSize(width: 720, height: 520))
            w.contentMinSize = NSSize(width: 640, height: 420)
            // Place it below the expanded notch so opening it from the notch
            // doesn't overlap the panel — unless it was moved or resized before.
            if !w.setFrameUsingName("CapeSettings") {
                if let screen = NSScreen.main {
                    let f = screen.frame
                    let x = f.midX - w.frame.width / 2
                    let y = f.maxY - (NotchRootView.panelHeight + 40) - w.frame.height
                    w.setFrameOrigin(NSPoint(x: x, y: y))
                } else {
                    w.center()
                }
            }
            w.setFrameAutosaveName("CapeSettings")
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

/// A page of the settings sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, tips, updates, notch, tabs, timer, tasks, buffer, screenTime, voice, tools, terminal, claude
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .tips: return String(localized: "Tips")
        case .updates: return String(localized: "Updates")
        case .notch: return String(localized: "Notch")
        case .tabs: return String(localized: "Tabs")
        case .timer: return String(localized: "Timer")
        case .tasks: return String(localized: "Tasks")
        case .buffer: return String(localized: "Buffer")
        case .screenTime: return String(localized: "Screen Time")
        case .voice: return String(localized: "Voice")
        case .tools: return String(localized: "Tools")
        case .terminal: return String(localized: "Terminal")
        case .claude: return String(localized: "Claude")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .tips: return "lightbulb.fill"
        case .updates: return "arrow.down.circle.fill"
        case .notch: return "rectangle.topthird.inset.filled"
        case .tabs: return "square.grid.2x2.fill"
        case .timer: return "timer"
        case .tasks: return "checklist"
        case .buffer: return "doc.on.clipboard.fill"
        case .screenTime: return "hourglass"
        case .voice: return "mic.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .terminal: return "terminal.fill"
        case .claude: return "sparkle"
        }
    }
    /// The rounded-square tile color, System Settings style.
    var color: Color {
        switch self {
        case .general: return .gray
        case .tips: return .yellow
        case .updates: return .coral
        case .notch: return Color(white: 0.2)
        case .tabs: return .indigo
        case .timer: return .red
        case .tasks: return .orange
        case .buffer: return .blue
        case .screenTime: return .purple
        case .voice: return .pink
        case .tools: return .teal
        case .terminal: return Color(red: 0.2, green: 0.62, blue: 0.35)
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    static let groups: [[SettingsPage]] = [
        [.general, .tips, .updates],
        [.notch, .tabs],
        [.timer, .tasks, .buffer, .screenTime, .voice, .tools, .terminal, .claude],
    ]
}

/// The selected settings page, remembered across launches (and set from the
/// notch to open straight on a page).
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "settingsPage") }
    }
    init() {
        page = UserDefaults.standard.string(forKey: "settingsPage").flatMap(SettingsPage.init) ?? .general
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var voice: VoiceDictation
    @ObservedObject var updater: Updater
    let buffer: BufferManager
    let claude: ClaudeSessionsManager
    let shell: ShellIntegration
    @ObservedObject var navigation: SettingsNavigation
    /// The picked icon couldn't be put on the bundle (a read-only place).
    @State private var iconFailed = false

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsPage?>(
                get: { navigation.page },
                set: { if let p = $0 { navigation.page = p } }
            )) {
                ForEach(SettingsPage.groups.indices, id: \.self) { i in
                    Section {
                        ForEach(SettingsPage.groups[i]) { page in
                            sidebarRow(page).tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Form { page(navigation.page) }
                .formStyle(.grouped)
                .navigationTitle(navigation.page.title)
                .id(navigation.page)   // start each page scrolled to the top
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        Label {
            HStack {
                Text(page.title)
                if page == .updates, updater.availableRelease != nil {
                    Spacer()
                    Circle().fill(Color.coral).frame(width: 7, height: 7)
                }
            }
        } icon: {
            Image(systemName: page.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(page.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: general
        case .tips: tips
        case .updates: Section { UpdatesSection(updater: updater, settings: settings) }
        case .notch: notch
        case .tabs: tabs
        case .timer: timer
        case .tasks: tasks
        case .buffer: bufferPage
        case .screenTime: screenTime
        case .voice: voicePage
        case .tools: tools
        case .terminal: TerminalPage(settings: settings, shell: shell)
        case .claude: claudePage
        }
    }

    // MARK: - Pages

    @ViewBuilder private var general: some View {
        Section {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Track Claude Code sessions", isOn: $settings.trackClaude)
                .onChange(of: settings.trackClaude) { on in if on { claude.installHooks() } }
        } footer: {
            Text("Claude tracking shows a pulsing blob while a session is thinking, and when your usage window resets.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker("Language", selection: $settings.appLanguage) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.label).tag($0.rawValue) }
            }
            if settings.appLanguage != AppLanguage.launched.rawValue {
                HStack {
                    Text("Cape switches language after a relaunch.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch Cape") { AppLanguage.relaunch() }
                }
            }
        } header: {
            Text("Language")
        }
        Section {
            HStack(spacing: 14) {
                ForEach(AppIconChoice.allCases) { choice in iconTile(choice) }
            }
            .padding(.vertical, 4)
            if iconFailed {
                Text("Couldn't change the icon of Cape.app here — move it to Applications and try again.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("App icon")
        } footer: {
            Text("Also in Finder, Launchpad and Spotlight — Launchpad can take a moment to catch up.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One icon to pick: its picture, its name, a coral ring when it's the one.
    private func iconTile(_ choice: AppIconChoice) -> some View {
        let picked = settings.appIcon == choice.rawValue
        return Button {
            settings.appIcon = choice.rawValue
            iconFailed = !choice.apply()
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let image = choice.image { Image(nsImage: image).resizable() }
                    else { RoundedRectangle(cornerRadius: 12).fill(.quaternary) }
                }
                .frame(width: 58, height: 58)
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(picked ? Color.coral : .clear, lineWidth: 2))
                Text(verbatim: choice.title)
                    .font(.caption)
                    .foregroundStyle(picked ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var tips: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome tour")
                    Text("The short intro from the first launch, in the notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show the tour") { NotificationCenter.default.post(name: .capeShowTour, object: nil) }
            }
        }
        Section("Basics") {
            tip("cursorarrow.rays", "Hover the notch",
                "It opens under the cursor and closes when you move away — no clicks needed.")
            tip("rectangle.split.3x1", "Tabs",
                "Music, Timer, Tasks, Buffer and Screen Time. Reorder or hide them in Settings › Tabs.")
            tip("arrow.up.and.down", "Taller panel",
                "Tasks, Buffer and Screen Time have a little bar at the bottom: tap it to make the panel taller.")
        }
        Section("Around the camera") {
            tip("music.note", "Music island",
                "Click it to pause or play; rest on it a moment to open Music.")
            tip("sparkle", "Claude island",
                "Coral while Claude works, amber when it waits for you, Clawd when it finished while you were away. Hover it for your sessions and Allow / Deny; slide left along the top to open the full panel.")
            tip("timer", "Timer and reminders",
                "Hover the countdown for pause / next / cancel. A ringing bell means a task is due — hover it to see which.")
        }
        Section("Handy") {
            tip("doc.on.clipboard", "Buffer",
                "Everything you copy is kept as a file: click to copy again, drag it out, ⭐ to pin. QR codes in copied screenshots become links.")
            tip("bell", "Times in words",
                "Write “call mom at 15:00” or “через 20 минут” in a task — the time becomes a reminder.")
            tip("mic", "Dictation",
                "Hold 🌐 Fn or right ⌥ to talk, or double-tap ⌥ — set it up in Settings › Voice.")
            tip("terminal", "cape done",
                "Add “; cape done” to a long command and get ✓ or ✗ in the notch — Settings › Terminal.")
            tip("wrench.and.screwdriver", "Tools",
                "Color picker, keyboard cleaning, Ports… Give a tool a shortcut in Settings › Tools.")
        }
    }

    private func tip(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.coral)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var notch: some View {
        Section("When it opens") {
            Picker("Default tab", selection: $settings.defaultModuleRaw) {
                ForEach(settings.enabledModules) { module in
                    Text(module.name).tag(module.rawValue)
                }
            }
            Stepper(value: $settings.recallMinutes, in: 1...240, step: 5) {
                Text("Back to the default tab after \(settings.recallMinutes) min")
            }
            Toggle("Open Media when hovering the music island", isOn: $settings.openMediaOnHover)
            Picker("While music plays, the island shows", selection: $settings.musicIslandCover) {
                Text("Equalizer").tag(false)
                Text("Album cover").tag(true)
            }
        }
        Section("Flashes") {
            Toggle("Show battery level when the charger connects", isOn: $settings.showCharging)
        }
    }

    @ViewBuilder private var tabs: some View {
        Section {
            ForEach(settings.orderedModules) { module in
                moduleRow(module)
            }
        } footer: {
            Text("Reorder the tabs with the arrows; switch one off to hide it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var timer: some View {
        Section("Breaks") {
            Stepper(value: $settings.shortBreakMinutes, in: 1...60) {
                Text("Short break: \(settings.shortBreakMinutes) min")
            }
            Stepper(value: $settings.longBreakMinutes, in: 1...60) {
                Text("Long break: \(settings.longBreakMinutes) min")
            }
        }
        Section("Sound") {
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
    }

    @ViewBuilder private var tasks: some View {
        Section {
            Toggle("Play a sound for reminders", isOn: $settings.reminderSound)
            if settings.reminderSound {
                SoundPicker(selection: $settings.reminderSoundName)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Add a time right in the task: “позвонить в 15:00”, “через 20 минут”, “завтра в 9”, “call mom at 3pm” — or pick one with the 🔔 button. It rings beside the notch when due.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var bufferPage: some View {
        Section("Storage") {
            HStack {
                Text("Folder")
                Spacer()
                Text(settings.bufferRootPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
                Button("Change…", action: pickFolder)
            }
        }
        Section {
            Toggle("Scan QR codes in copied images", isOn: $settings.scanQRInImages)
        } header: {
            Text("QR codes")
        } footer: {
            Text("When a copied image holds QR codes, each one's link is added to the buffer as its own entry, right under the image. Screenshots count only when they go to the clipboard: ⌃⇧⌘3 and ⌃⇧⌘4 always do; with ⇧⌘3, ⇧⌘4 or ⇧⌘5 they're saved as files (e.g. on the Desktop) and aren't scanned — in ⇧⌘5 › Options › Save to, pick Clipboard.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Cleanup") {
            Stepper(value: $settings.bufferRetentionDays, in: 1...90) {
                Text("Clear buffer older than \(settings.bufferRetentionDays) days")
            }
            .onChange(of: settings.bufferRetentionDays) { _ in buffer.applySettings() }
            .disabled(settings.clearBufferAtEndOfDay)

            Toggle("Delete each day's buffer at end of day", isOn: $settings.clearBufferAtEndOfDay)
                .onChange(of: settings.clearBufferAtEndOfDay) { _ in buffer.applySettings() }
        }
    }

    @ViewBuilder private var screenTime: some View {
        Section {
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
        Section {
            Picker("Count battery use", selection: $settings.energyOnBatteryOnly) {
                Text("Only on battery").tag(true)
                Text("All the time").tag(false)
            }
        } header: {
            Text("Battery use")
        } footer: {
            Text("The ⚡ button in Screen Time shows how much of a full charge each app used, and it adds up to what the battery really lost. An app gets its own work (macOS measures every process) plus the screen and the rest of the Mac while it was in front, as on the iPhone; time away goes to macOS. Hover a figure for the split. Both counts are kept, so switching here changes the figures at once.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var voicePage: some View {
        Section {
            Picker("Dictation model", selection: $settings.voiceModel) {
                ForEach(VoiceModels.options, id: \.id) {
                    Text($0.label + (Transcriber.isModelDownloaded($0.id) ? "  ✓" : "")).tag($0.id)
                }
            }
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
            Toggle("Preload model at launch (faster first dictation)", isOn: $settings.voicePreload)
        } header: {
            Text("Model")
        } footer: {
            Text("Downloaded once, runs on this Mac. Bigger = more accurate, more RAM.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker("Language", selection: $settings.voiceLanguage) {
                ForEach(VoiceModels.languages, id: \.id) { Text($0.label).tag($0.id) }
            }
            Toggle("Translate to English", isOn: $settings.voiceTranslate)
        } header: {
            Text("Language")
        } footer: {
            Text("Auto-detect can misread some languages (e.g. Russian) — pick it explicitly if needed. A transcript starting with “заметка”/“note” goes to the Tasks list.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
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
        } header: {
            Text("Keys")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if settings.voiceHoldFn || settings.voiceHoldRightOption {
                    Text("Hold the key to record, release to transcribe. A quick press keeps working as usual. If the emoji picker pops up when you let go of 🌐, set System Settings › Keyboard › “Press 🌐 key to” › Do Nothing.")
                }
                Text("The keys need Accessibility permission.")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var tools: some View {
        Section {
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
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Global shortcuts need ⌘, ⌥ or ⌃. While recording, Esc cancels and ⌫ clears. No extra permissions needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Reverse the mouse wheel (trackpad stays natural)", isOn: $settings.reverseMouseScroll)
        } header: {
            Text("Mouse")
        } footer: {
            Text("Needs Accessibility. Turn off Scroll Reverser or similar apps, or the wheel is flipped twice.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var claudePage: some View {
        Section {
            Toggle("Answer permission requests from the notch", isOn: $settings.claudeApprovals)
                .disabled(!settings.trackClaude)
            if settings.claudeApprovals {
                Picker("Hand back to the terminal after", selection: $settings.claudeApprovalTimeout) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                }
                .disabled(!settings.trackClaude)
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("Hover the Claude island beside the camera to see your sessions — working, done, or waiting for you (amber). When Claude asks to run a tool, Allow or Deny it right there; unanswered, the question goes back to the terminal or the Claude app. While it waits for the notch, Claude waits too. Works in the terminal and in the Claude app's Code tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Show Clawd when a session finishes while you're away", isOn: $settings.claudeMascot)
                .disabled(!settings.trackClaude)
            if settings.claudeMascot {
                Picker("Clawd waits for you", selection: $settings.claudeMascotMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("3 hours").tag(180)
                }
                .disabled(!settings.trackClaude)
                Picker("Falls asleep after", selection: $settings.claudeMascotSleepMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                }
                .disabled(!settings.trackClaude)
                if settings.claudeMascotSleepMinutes >= settings.claudeMascotMinutes {
                    Text("He'd leave before falling asleep — pick less than “Clawd waits for you”.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } footer: {
            Text("Claude's little critter sits in the island until you look: click it, pick the session in the list, or switch to the app it runs in — he leaves with a happy hop. A session that finishes while its app is in front doesn't call him — you saw it. Waited too long: he dozes off (hover to wake him), and in the end waves and walks home behind the camera; quitting that app sends him home too. Up to four stand side by side, one per session.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
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
        } footer: {
            if !settings.trackClaude {
                HStack(spacing: 4) {
                    Text("Turn on “Track Claude Code sessions” in")
                    Button("General") { navigation.page = .general }.buttonStyle(.link)
                    Text("to use this.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
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
        alert.messageText = String(localized: "Delete the dictation model?")
        alert.informativeText = String(localized: "It will be removed from disk. You can re-download it any time from here.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { voice.deleteModel() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
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

/// Settings › Terminal: install the zsh integration, `cape done`, long commands.
private struct TerminalPage: View {
    @ObservedObject var settings: Settings
    let shell: ShellIntegration
    @State private var installed = false
    @State private var error: String?

    var body: some View {
        Section {
            HStack {
                if installed {
                    Label("Installed in ~/.zshrc", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("Not installed")
                }
                Spacer()
                Button(installed ? String(localized: "Remove") : String(localized: "Install")) {
                    do {
                        try installed ? shell.uninstall() : shell.install()
                        error = nil
                    } catch { self.error = error.localizedDescription }
                    installed = shell.isInstalled
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: {
            Text("zsh")
        } footer: {
            Text("Adds one line to ~/.zshrc (a backup is kept as ~/.zshrc.cape-backup). Open a new terminal tab afterwards, or run “source ~/.zshrc”. Works with Oh My Zsh.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("npm run build; cape done").font(.system(.callout, design: .monospaced))
                Text("swift test; cape done").font(.system(.callout, design: .monospaced))
            }
            .textSelection(.enabled)
            Toggle("Play a sound", isOn: $settings.shellSound)
        } header: {
            Text("cape done")
        } footer: {
            Text("Add “; cape done” to any command: when it ends, the notch flashes ✓ or ✗ with the command and how long it took (Glass on success, Basso on failure).")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Toggle("Flash after long commands", isOn: $settings.shellAuto)
            if settings.shellAuto {
                Picker("Long means over", selection: $settings.shellAutoSeconds) {
                    Text("10 seconds").tag(10)
                    Text("20 seconds").tag(20)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
            }
        } header: {
            Text("Long commands")
        } footer: {
            Text("The same flash without typing “cape done” — only when you're in another window (not while the terminal is in front), and not for editors, ssh, claude, less, top and the like.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { installed = shell.isInstalled }
    }
}
