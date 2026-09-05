import SwiftUI

struct PomodoroPanel: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var claude: ClaudeSessionsManager

    private var accent: Color { phaseColor(model.phase) }

    var body: some View {
        VStack(spacing: 8) {
            timerRow
            claudeReadyLine
        }
    }

    private var timerRow: some View {
        HStack(spacing: 20) {
            // Progress ring with the countdown.
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: model.progress)
                VStack(spacing: 1) {
                    Text(formatTime(model.timeRemaining))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(model.phase.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 118, height: 118)

            VStack(spacing: 10) {
                presets

                Button(action: model.toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        Text(model.isRunning ? "Pause" : "Start")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: 156, height: 38)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    iconButton("arrow.counterclockwise", "Reset", action: model.reset)
                    iconButton("forward.fill", "Skip", action: model.skip)
                }
            }
        }
    }

    /// Coral note: when a Claude usage limit is hit, show when it frees up;
    /// celebrate briefly once it does. Nothing while Claude is available.
    private var claudeReadyLine: some View {
        TimelineView(.periodic(from: Date(), by: 20)) { ctx in
            Group {
                if let text = readyText(now: ctx.date) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                        Text(text).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.coral)
                    .transition(.opacity)
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }

    private func readyText(now: Date) -> String? {
        guard let reset = claude.limitResetAt else { return nil }
        if now < reset {
            // Blocked (at/over 100%) vs merely nearing the limit — word it honestly.
            return claude.limitBlocked
                ? "Claude will be ready at \(clock(reset))"
                : "Claude limits reset at \(clock(reset))"
        }
        // Celebrate for an hour after the reset, then fall silent.
        if now < reset.addingTimeInterval(60 * 60) { return "Claude is ready!" }
        return nil
    }

    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        // Add the weekday when the reset isn't today (e.g. a weekly limit).
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }

    private var presets: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(PomodoroModel.presets.prefix(3), id: \.self) { presetChip($0) }
            }
            HStack(spacing: 5) {
                ForEach(PomodoroModel.presets.suffix(3), id: \.self) { presetChip($0) }
            }
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        let selected = model.phase == .work && model.workMinutes == minutes
        return Button { model.setWorkMinutes(minutes) } label: {
            Text("\(minutes)")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 48, height: 24)
                .background(selected ? accent.opacity(0.9) : Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(width: 74, height: 34)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
