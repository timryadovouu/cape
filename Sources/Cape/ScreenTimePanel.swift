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
    @State private var filter: AppCategory?          // tap a category to list only its apps

    private var stats: DayStats {
        offset == 0 ? usage.today : (cached ?? .empty(dateFor(offset)))
    }

    var body: some View {
        VStack(spacing: 10) {
            dateHeader
            if showChart { weekChart }

            HStack(spacing: 16) {
                stat(title: "Total", value: formatDuration(stats.total))
                stat(title: "Switches", value: "\(stats.switches)")
                Spacer(minLength: 8)
                if !breakdown.isEmpty {
                    categoryLegend
                    CategoryDonut(slices: breakdown, highlighted: filter)
                        .frame(width: 38, height: 38)
                }
            }

            if stats.apps.isEmpty {
                Spacer()
                Text(offset == 0 ? "Tracking starts now" : "No activity that day")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(shownApps.prefix(settings.screenTimeAppCount)) { row($0) }
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
            filter = nil
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

    // MARK: - Categories

    /// Time per category for the shown day, largest first (empty ones left out).
    private var breakdown: [(category: AppCategory, seconds: Int)] {
        var sums: [AppCategory: Int] = [:]
        for app in stats.apps { sums[AppCategory.of(path: app.iconPath), default: 0] += app.seconds }
        return AppCategory.allCases.compactMap { c in sums[c].flatMap { $0 > 0 ? (c, $0) : nil } }
            .sorted { $0.seconds > $1.seconds }
    }

    private var shownApps: [AppUsage] {
        guard let filter else { return stats.apps }
        return stats.apps.filter { AppCategory.of(path: $0.iconPath) == filter }
    }

    /// "● Work 52%" per category, two columns; a tap filters the app list.
    private var categoryLegend: some View {
        let total = max(1, breakdown.reduce(0) { $0 + $1.seconds })
        return LazyVGrid(columns: [GridItem(.fixed(112), spacing: 8, alignment: .leading),
                                   GridItem(.fixed(112), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 3) {
            ForEach(breakdown, id: \.category) { slice in
                let share = Double(slice.seconds) / Double(total)
                let dimmed = filter != nil && filter != slice.category
                Button { filter = filter == slice.category ? nil : slice.category } label: {
                    HStack(spacing: 5) {
                        Circle().fill(slice.category.color).frame(width: 6, height: 6)
                        Text(slice.category.name)
                            .font(.system(size: 10, weight: filter == slice.category ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Text(share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%")
                            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .opacity(dimmed ? 0.35 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(filter == slice.category ? "Show all apps" : "Show only \(slice.category.name) apps")
            }
        }
        .fixedSize()
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
                    Capsule().fill(AppCategory.of(path: app.iconPath).color)   // its category's color
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

/// A small ring split by category share; the highlighted slice stays bright.
private struct CategoryDonut: View {
    let slices: [(category: AppCategory, seconds: Int)]
    let highlighted: AppCategory?

    var body: some View {
        let total = Double(max(1, slices.reduce(0) { $0 + $1.seconds }))
        // Tiny gaps between slices (none when there's only one).
        let gap = slices.count > 1 ? 0.012 : 0
        ZStack {
            ForEach(Array(segments(total).enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.from, to: max(seg.from, seg.to - gap))
                    .stroke(seg.category.color, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .opacity(highlighted == nil || highlighted == seg.category ? 1 : 0.25)
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(3.5)
        .animation(.easeOut(duration: 0.2), value: highlighted)
    }

    private func segments(_ total: Double) -> [(category: AppCategory, from: Double, to: Double)] {
        var start = 0.0
        return slices.map { slice in
            let end = start + Double(slice.seconds) / total
            defer { start = end }
            return (slice.category, start, end)
        }
    }
}
