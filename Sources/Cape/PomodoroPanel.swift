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

    /// The tick ring on the left, a compact column of controls on the right.
    /// Every button has the rail's rounded-square shape.
    private var timerRow: some View {
        HStack(spacing: 36) {
            ZStack {
                TickRing(remaining: 1 - model.progress, color: accent)
                VStack(spacing: 2) {
                    Text(formatTime(model.timeRemaining))
                        .font(.system(size: 30, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                    Text(model.phase.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 146, height: 146)

            VStack(spacing: 7) {
                presets

                Button(action: model.toggle) {
                    HStack(spacing: 7) {
                        Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(model.isRunning ? String(localized: "Pause") : String(localized: "Start"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    iconButton("arrow.counterclockwise", String(localized: "Reset"), action: model.reset)
                    iconButton("forward.fill", String(localized: "Skip"), action: model.skip)
                }
            }
            .frame(width: 216)
        }
        .frame(maxWidth: .infinity)
    }

    /// The rail's tabs use 9; one shape for every button here.
    private static let radius: CGFloat = 9

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
                ? String(localized: "Claude will be ready at \(clock(reset))")
                : String(localized: "Claude limits reset at \(clock(reset))")
        }
        // Celebrate for an hour after the reset, then fall silent.
        if now < reset.addingTimeInterval(60 * 60) { return String(localized: "Claude is ready!") }
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
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(selected ? accent.opacity(0.9) : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A ring of 60 ticks, like a kitchen timer's LED dial: lit for the time
/// left, going dark clockwise from the top as it runs, on a dark glass disc
/// with a thin rim.
private struct TickRing: View {
    var remaining: Double
    var color: Color
    private let count = 60

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 7      // room for the disc's rim
            let length: CGFloat = 9, width: CGFloat = 4
            let rim = r + 6
            let disc = Path(ellipseIn: CGRect(x: c.x - rim, y: c.y - rim, width: rim * 2, height: rim * 2))
            ctx.fill(disc, with: .color(Color.white.opacity(0.05)))
            ctx.stroke(disc, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
            let elapsed = Int(((1 - remaining) * Double(count)).rounded(.down))
            for i in 0..<count {
                var tick = ctx
                tick.translateBy(x: c.x, y: c.y)
                tick.rotate(by: .degrees(Double(i) * 360 / Double(count)))
                let rect = CGRect(x: -width / 2, y: -r, width: width, height: length)
                tick.fill(Path(roundedRect: rect, cornerRadius: width / 2.5),
                          with: .color(i >= elapsed ? color : Color.white.opacity(0.1)))
            }
        }
        .animation(.easeOut(duration: 0.3), value: remaining)
    }
}
