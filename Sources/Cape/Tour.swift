import SwiftUI

extension Notification.Name {
    /// Settings › Tips asks the notch to run the welcome tour again.
    static let capeShowTour = Notification.Name("io.cape.showTour")
}

/// One stop of the welcome tour.
enum TourStep: Equatable {
    case welcome
    case module(Module)     // the real tab, live
    case tools              // the real Tools page
    case islands            // a drawing of the closed brow and its islands
    case setup              // switches for what to turn on
}

/// The welcome tour: a walk through the real notch — it opens tall, switches
/// to each tab in turn (highlighted in the rail) and explains it in a strip at
/// the bottom. Shown on the first launch and from Settings › Tips; the notch
/// stays open until it's finished or skipped. Tabs switched off are skipped.
enum Tour {
    static let doneKey = "tourDone"

    /// A fresh install hasn't seen it; someone who already used Cape (it
    /// remembered a last-opened time) doesn't need it after an update.
    static var shouldShowOnLaunch: Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: doneKey) { return false }
        if d.object(forKey: "lastOpenAt") != nil { d.set(true, forKey: doneKey); return false }
        return true
    }

    static func steps(_ settings: Settings) -> [TourStep] {
        [.welcome] + settings.enabledModules.map(TourStep.module) + [.tools, .islands, .setup]
    }

    /// Go to step `index`: show its tab / page.
    static func show(_ index: Int, state: NotchState, settings: Settings) {
        let all = steps(settings)
        guard all.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            state.tourStep = index
            state.showingPorts = false
            switch all[index] {
            case .module(let m): state.selectModule(m)
            case .tools: state.showingTools = true
            default: state.showingTools = false
            }
        }
    }

    static func finish(state: NotchState, settings: Settings) {
        UserDefaults.standard.set(true, forKey: doneKey)
        state.tourStep = nil
        state.showingTools = false
        state.selectModule(settings.defaultModule)
        state.tall = false
    }
}

// MARK: - The strip at the bottom

struct TourCaption: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings

    private var steps: [TourStep] { Tour.steps(settings) }
    private var index: Int { state.tourStep ?? 0 }
    private var step: TourStep { steps.indices.contains(index) ? steps[index] : .welcome }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            text
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(steps.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Color.coral : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                if !isLast {
                    Button { Tour.finish(state: state, settings: settings) } label: {
                        Text("Skip tour").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                if index > 0 {
                    pill("Back", fill: Color.white.opacity(0.14)) {
                        Tour.show(index - 1, state: state, settings: settings)
                    }
                }
                if isLast {
                    pill("Done", fill: Color.coral) { Tour.finish(state: state, settings: settings) }
                } else {
                    pill("Next", fill: Color.coral) { Tour.show(index + 1, state: state, settings: settings) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.coral.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.white)
    }

    private var title: some View {
        Group {
            switch step {
            case .welcome: Text("Welcome to Cape")
            case .module(let m): Text(verbatim: m.name)
            case .tools: Text("Tools")
            case .islands: Text("Around the camera")
            case .setup: Text("Turn on what you need")
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }

    @ViewBuilder private var text: some View {
        switch step {
        case .welcome:
            Text("Cape lives in your notch: hover it to open, move away to close. Here's a quick look around — everything is also in Settings › Tips.")
        case .module(.media):
            Text("Spotify or cmus: the cover, click or drag the bar to seek, click the time for time left. F7–F9 work for cmus too.")
        case .module(.timer):
            Text("Pomodoro with a countdown beside the notch — hover it for pause / next / cancel without opening the panel.")
        case .module(.tasks):
            Text("Write the time in words — “call mom at 15:00”, “через 20 минут” — and a bell rings when it's due. The 🔔 on a task opens its card with a calendar.")
        case .module(.buffer):
            Text("Everything you copy lands here: click to copy again, drag out, ⭐ to pin. 🎙 Dictation too — start with “note” or “заметка” and it goes to Tasks instead, time and all: “note call mom at 3pm”.")
        case .module(.screenTime):
            Text("Where the day went, by app and by category — and with ⚡, how much of the battery each app used: “46m · 6%”. Click a category to filter; the chart button shows the week.")
        case .tools:
            Text("Color picker, keyboard cleaning, reversed mouse wheel, links from QR codes in screenshots, and Ports — what's running on localhost.")
        case .islands:
            Text("With the notch closed, small islands show what's going on. They're clickable — hover or click them.")
        case .setup:
            Text("macOS asks for a permission only when a feature first needs it. The rest is in Settings.")
        }
    }

    private func pill(_ key: LocalizedStringKey, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(fill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pages of their own (welcome, islands, setup)

/// What fills the panel on the steps that aren't a real tab.
struct TourPage: View {
    let step: TourStep
    @ObservedObject var settings: Settings
    let modules: AppModules

    var body: some View {
        switch step {
        case .islands: islands
        case .setup: setup
        default: welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 84, height: 84)
            }
            Text(verbatim: "Cape").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("the peninsula in your notch")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A drawing of the closed brow on a slice of screen, then what each island does.
    private var islands: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.17))
                    .frame(height: 64)
                HStack(spacing: 0) {
                    island(width: 40) { EqualizerBars(color: Color(red: 0.35, green: 0.85, blue: 0.45)) }
                    Color.clear.frame(width: 150)                    // the camera
                    island(width: 40) { ClaudeBlob().frame(width: 11, height: 11) }
                    island(width: 66) {
                        Text(verbatim: "24:13").font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(Color.coral)
                    }
                    island(width: 34) { RingingBell() }
                }
                .frame(height: 30)
                .background(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 12, bottomTrailing: 12),
                                                   style: .continuous).fill(Color.black))
            }
            .frame(maxWidth: 420)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 8) {
                legend("music.note", "Music", "click: pause / play · hold: open Music")
                legend("sparkle", "Claude", "coral: working · amber: waits for you · hover: sessions")
                legend("timer", "Timer", "hover: pause / next / cancel")
                legend(nil, "Clawd", "a session finished while you were away — click to go to it")
                legend("bell.fill", "Reminder", "a task is due — hover to open Tasks")
                legend("doc.on.clipboard", "Flashes", "copy, picked color, QR link, cape done")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private func island<Content: View>(width: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: width, height: 30)
    }

    /// A line of the legend; no icon means Clawd himself.
    private func legend(_ icon: String?, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Color.coral)
                } else {
                    Clawd(pixel: 1, lively: false).padding(.top, 2)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            switchRow("Launch at login", on: settings.launchAtLogin) { settings.launchAtLogin.toggle() }
            switchRow("Track Claude Code sessions", on: settings.trackClaude) {
                settings.trackClaude.toggle()
                if settings.trackClaude { modules.claude.installHooks() }
            }
            switchRow("Flash after long terminal commands", on: settings.shellAuto) { settings.shellAuto.toggle() }
            Divider().overlay(Color.white.opacity(0.1))
            link("lightbulb", "All the tips — Settings › Tips") { modules.settingsWindow.show(.tips) }
            link("mic", "Dictation keys — Settings › Voice") { modules.settingsWindow.show(.voice) }
            link("terminal", "Install cape done — Settings › Terminal") { modules.settingsWindow.show(.terminal) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 6)
        .padding(.horizontal, 6)
    }

    private func link(_ icon: String, _ key: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(key, systemImage: icon).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    /// A setting with the notch's coral switch (the system one is washed out on black).
    private func switchRow(_ key: LocalizedStringKey, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                CoralSwitch(isOn: on)
                Text(key).font(.system(size: 12.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
