import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case media, timer, tasks, buffer, screenTime
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .media: return "music.note"
        case .timer: return "timer"
        case .tasks: return "checklist"
        case .buffer: return "doc.on.clipboard"
        case .screenTime: return "hourglass"
        }
    }

    var name: String {
        switch self {
        case .media: return "Media"
        case .timer: return "Timer"
        case .tasks: return "Tasks"
        case .buffer: return "Buffer"
        case .screenTime: return "Screen Time"
        }
    }
}

/// Contents of the expanded brow: live system metrics flanking the camera, an
/// icon rail, and the active module.
struct ExpandedPanel: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    @ObservedObject var system: SystemStats
    let modules: AppModules
    let notchWidth: CGFloat
    let topInset: CGFloat

    private var current: Module {
        settings.isEnabled(state.currentModule)
            ? state.currentModule
            : (settings.enabledModules.first ?? .tasks)
    }

    var body: some View {
        VStack(spacing: 8) {
            headerMetrics.frame(height: topInset)
            rail
            Group {
                switch current {
                case .media: MediaPanel(media: modules.media)
                case .timer: PomodoroPanel(model: modules.pomodoro, claude: modules.claude)
                case .tasks: TodoPanel(store: modules.todo, state: state)
                case .buffer: BufferPanel(manager: modules.buffer, state: state, voice: modules.voice)
                case .screenTime: ScreenTimePanel(usage: modules.usage, state: state, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    // MARK: - System metrics (in the black areas beside the camera)

    private var headerMetrics: some View {
        HStack(spacing: 0) {
            metric("CPU", system.cpu, "\(Int(system.cpu * 100))%",
                   Color(red: 1.0, green: 0.45, blue: 0.4))
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)   // camera gap

            metric("RAM", system.ramFraction, ramValue,
                   Color(red: 0.4, green: 0.75, blue: 1.0))
                .frame(maxWidth: .infinity)
        }
    }

    private var ramValue: String {
        let gb = 1_073_741_824.0
        return String(format: "%.1f/%d GB", system.ramUsed / gb, Int((system.ramTotal / gb).rounded()))
    }

    private func metric(_ label: String, _ fraction: Double, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 30, alignment: .leading)
            Capsule().fill(Color.white.opacity(0.14))
                .frame(width: 54, height: 7)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: 54 * min(1, max(0.03, fraction)), height: 7)
                }
            Text(value)
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize()
        }
    }

    // MARK: - Rail

    private var rail: some View {
        HStack(spacing: 5) {
            ForEach(settings.enabledModules) { module in
                tab(module)
            }
            iconButton("gearshape.fill",
                       tint: Color(red: 0.980, green: 0.514, blue: 0.302), // #FA834D coral
                       help: "Settings") {
                modules.settingsWindow.toggle()
            }
            Button { NSApp.terminate(nil) } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .bold))
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Quit mac-notch")
        }
    }

    private func tab(_ module: Module) -> some View {
        let active = current == module
        return Button { state.selectModule(module) } label: {
            Image(systemName: module.icon)
                .font(.system(size: 13, weight: active ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .foregroundStyle(active ? .white : .white.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? Color.white.opacity(0.24) : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(active ? 0.35 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(module.name)
    }

    private func iconButton(_ icon: String, tint: Color, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 40, height: 32)
                .foregroundStyle(tint)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
