import SwiftUI

struct ScreenTimePanel: View {
    @ObservedObject var usage: AppUsageTracker
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    @State private var offset = 0                 // 0 = today, -1 = yesterday…
    @State private var cached: DayStats? = nil     // loaded stats for a past day
    @State private var earliest = 0
    @State private var weekTotals: [Int: Int] = [:]  // offset -> total, for the shown week
    @State private var showChart = false             // week chart hidden by default

    private var stats: DayStats {
        offset == 0 ? usage.today : (cached ?? .empty(dateFor(offset)))
    }

    var body: some View {
        VStack(spacing: 10) {
            dateHeader
            if showChart { weekChart }

            HStack {
                stat(title: "Total", value: formatDuration(stats.total))
                Spacer()
                stat(title: "Switches", value: "\(stats.switches)")
            }

            if stats.apps.isEmpty {
                Spacer()
                Text(offset == 0 ? "Tracking starts now" : "No activity that day")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(stats.apps.prefix(settings.screenTimeAppCount)) { row($0) }
                    }
                }
            }

            GrabberBar(state: state)
        }
        .onAppear {
            earliest = usage.earliestOffset()
            loadWeek()
        }
        .onChange(of: offset) { newOffset in
            cached = newOffset == 0 ? nil : usage.loadDay(offset: newOffset)
            earliest = usage.earliestOffset()
            loadWeek()
        }
    }

    /// Offsets (relative to today) of Mon…Sun for the week that contains `day`.
    private func weekOffsets(for day: Int) -> [Int] {
        let weekday = Calendar.current.component(.weekday, from: dateFor(day))  // 1=Sun … 7=Sat
        let mondayOffset = (weekday + 5) % 7                                    // Mon=0 … Sun=6
        return (0 ... 6).map { day - mondayOffset + $0 }
    }

    /// Load daily totals for the week that contains the selected day.
    private func loadWeek() {
        var totals: [Int: Int] = [:]
        for off in weekOffsets(for: offset) where off < 0 {
            totals[off] = usage.loadDay(offset: off).total
        }
        weekTotals = totals
    }

    // MARK: - Week chart

    private var weekChart: some View {
        // The Monday–Sunday week that contains the *selected* day, so paging back
        // moves the chart to that day's week. Future days (only ever in the
        // current week) show empty and aren't selectable.
        let bars = weekOffsets(for: offset).map { off -> (Int, Int, Bool) in
            let total = off == 0 ? usage.totalSeconds : (weekTotals[off] ?? 0)
            return (off, total, off <= 0)
        }
        let maxV = max(1, bars.map { $0.1 }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(bars, id: \.0) { off, total, selectable in
                let selected = off == offset
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(selected ? Color(red: 0.4, green: 0.7, blue: 1.0)
                                       : Color.white.opacity(selectable ? 0.16 : 0.06))
                        .frame(height: max(3, CGFloat(total) / CGFloat(maxV) * 32))
                    Text(dayLetter(off))
                        .font(.system(size: 8, weight: selected ? .bold : .regular))
                        .foregroundStyle(selected ? .white : .white.opacity(selectable ? 0.4 : 0.2))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { if selectable { offset = off } }
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    private func dayLetter(_ off: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"   // single-letter weekday
        return f.string(from: dateFor(off))
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack {
            Color.clear.frame(width: 28, height: 1)   // balances the chart toggle on the right
            navButton("chevron.left", enabled: offset > earliest) { offset -= 1 }
            Spacer()
            Text(dateLabel)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            navButton("chevron.right", enabled: offset < 0) { offset += 1 }
            Button { showChart.toggle() } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(showChart ? Color(red: 0.4, green: 0.7, blue: 1.0) : .white.opacity(0.5))
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(showChart ? "Hide week chart" : "Show week chart")
        }
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(enabled ? 0.8 : 0.25))
        .disabled(!enabled)
    }

    private var dateLabel: String {
        switch offset {
        case 0: return "Today"
        case -1: return "Yesterday"
        default:
            let f = DateFormatter(); f.dateFormat = "EEE, d MMM"
            return f.string(from: dateFor(offset))
        }
    }

    private func dateFor(_ o: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: o, to: Date()) ?? Date()
    }

    // MARK: - Rows

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }

    private func row(_ app: AppUsage) -> some View {
        let fraction = stats.total > 0 ? Double(app.seconds) / Double(stats.total) : 0
        return VStack(spacing: 3) {
            HStack(spacing: 7) {
                Group {
                    if let path = app.iconPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                    } else {
                        Image(systemName: "app.dashed").resizable()
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 16, height: 16)
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(formatDuration(app.seconds))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color(red: 0.4, green: 0.7, blue: 1.0))
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}
