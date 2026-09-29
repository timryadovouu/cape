import SwiftUI

/// Screen Time: the day's apps by time — or by battery use (the ⚡ toggle).
/// Each row shows both ("2h 10m · 7%"); the toggle decides the order, the bars,
/// the total, the category ring and the week chart.
struct ScreenTimePanel: View {
    @ObservedObject var usage: AppUsageTracker
    @ObservedObject var energy: EnergyMonitor
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    @State private var offset = 0                 // 0 = today, -1 = yesterday…
    @State private var cached: DayStats? = nil     // loaded stats for a past day
    @State private var cachedEnergy: [String: EnergyMonitor.AppEnergy] = [:]
    @State private var earliest = 0
    @State private var weekTotals: [Int: Int] = [:]      // offset -> seconds, for the shown week
    @State private var weekEnergy: [Int: Double] = [:]   // offset -> joules
    @State private var showChart = false             // week chart hidden by default
    @State private var filter: AppCategory?          // tap a category to list only its apps

    private var stats: DayStats {
        offset == 0 ? usage.today : (cached ?? .empty(dateFor(offset)))
    }
    private var byEnergy: Bool { settings.screenTimeByEnergy }
    private var energyDay: [String: EnergyMonitor.AppEnergy] { offset == 0 ? energy.today : cachedEnergy }

    /// One app with both measures (Screen Time's minutes, the energy monitor's joules).
    private struct Row: Identifiable {
        let id: String
        let name: String
        let iconPath: String?
        var seconds = 0
        var joules = 0.0
        var screenJoules = 0.0      // of `joules`: the screen and system while it was in front
    }

    /// The day's apps, merged by bundle path, ordered by the chosen measure.
    private var rows: [Row] {
        var out: [String: Row] = [:]
        for app in stats.apps {
            let key = app.iconPath ?? app.name
            out[key] = Row(id: key, name: app.name, iconPath: app.iconPath, seconds: app.seconds)
        }
        for (key, e) in energyDay {
            let j = energy.joules(e), sj = energy.screenJoules(e)
            guard j > 0 else { continue }
            // Same bundle path — or, failing that, the same name (Safari runs from
            // a different path than the one it shows).
            let match = out[key] != nil ? key : out.first { $0.value.name == e.name }?.key
            if let match {
                out[match]?.joules += j
                out[match]?.screenJoules += sj
            } else {
                out[key] = Row(id: key, name: e.name, iconPath: key.hasSuffix(".app") ? key : nil,
                               joules: j, screenJoules: sj)
            }
        }
        return out.values.filter { value($0) > 0 }.sorted { value($0) > value($1) }
    }

    private func value(_ r: Row) -> Double { byEnergy ? r.joules : Double(r.seconds) }
    private var dayTotal: Double { rows.reduce(0) { $0 + value($1) } }

    var body: some View {
        VStack(spacing: 10) {
            dateHeader
            if showChart { weekChart }

            HStack(spacing: 16) {
                if byEnergy {
                    stat(title: String(localized: "Battery"), value: "≈" + EnergyMonitor.label(dayTotal))
                } else {
                    stat(title: String(localized: "Total"), value: formatDuration(stats.total))
                }
                stat(title: String(localized: "Switches"), value: "\(stats.switches)")
                Spacer(minLength: 8)
                if !breakdown.isEmpty {
                    categoryLegend
                    CategoryDonut(slices: breakdown, highlighted: filter)
                        .frame(width: 38, height: 38)
                }
            }

            if rows.isEmpty {
                Spacer()
                Text(emptyText)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(shownRows.prefix(settings.screenTimeAppCount)) { row($0) }
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
            cachedEnergy = newOffset == 0 ? [:] : energy.day(offset: newOffset)
            earliest = usage.earliestOffset()
            loadWeek()
        }
        .onChange(of: byEnergy) { _ in filter = nil }
    }

    private var emptyText: String {
        guard byEnergy else {
            return offset == 0 ? String(localized: "Tracking starts now") : String(localized: "No activity that day")
        }
        if settings.energyOnBatteryOnly {
            return offset == 0 ? String(localized: "Nothing on battery yet today — it's counted off the charger")
                               : String(localized: "Nothing on battery that day")
        }
        return offset == 0 ? String(localized: "Counting starts now — the first figures come within a minute")
                           : String(localized: "No battery data for that day")
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
        var joules: [Int: Double] = [:]
        for off in weekOffsets(for: offset) where off < 0 {
            totals[off] = usage.loadDay(offset: off).total
            joules[off] = energy.day(offset: off).values.reduce(0) { $0 + energy.joules($1) }
        }
        weekTotals = totals
        weekEnergy = joules
    }

    // MARK: - Week chart

    private var weekChart: some View {
        // The Monday–Sunday week that contains the *selected* day, so paging back
        // moves the chart to that day's week. Future days (only ever in the
        // current week) show empty and aren't selectable.
        let bars = weekOffsets(for: offset).map { off -> (Int, Double, Bool) in
            let total: Double
            if byEnergy {
                total = off == 0 ? energy.today.values.reduce(0) { $0 + energy.joules($1) } : (weekEnergy[off] ?? 0)
            } else {
                total = Double(off == 0 ? usage.totalSeconds : (weekTotals[off] ?? 0))
            }
            return (off, total, off <= 0)
        }
        let maxV = max(1e-9, bars.map { $0.1 }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(bars, id: \.0) { off, total, selectable in
                let selected = off == offset
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(selected ? (byEnergy ? Color.coral : Color(red: 0.4, green: 0.7, blue: 1.0))
                                       : Color.white.opacity(selectable ? 0.16 : 0.06))
                        .frame(height: max(3, CGFloat(total / maxV) * 32))
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
        let f = DateFormatter(); f.locale = AppLanguage.locale; f.dateFormat = "EEEEE"   // single-letter weekday
        return f.string(from: dateFor(off))
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack {
            // Time ⇄ battery use (balances the chart toggle on the right).
            Button { settings.screenTimeByEnergy.toggle() } label: {
                Image(systemName: byEnergy ? "bolt.fill" : "clock")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(byEnergy ? Color.coral : .white.opacity(0.5))
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(byEnergy ? String(localized: "By time") : String(localized: "By battery use"))
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
            .help(showChart ? String(localized: "Hide week chart") : String(localized: "Show week chart"))
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
        case 0: return String(localized: "Today")
        case -1: return String(localized: "Yesterday")
        default:
            let f = DateFormatter(); f.locale = AppLanguage.locale; f.dateFormat = "EEE, d MMM"
            return f.string(from: dateFor(offset))
        }
    }

    private func dateFor(_ o: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: o, to: Date()) ?? Date()
    }

    // MARK: - Categories

    /// The chosen measure per category for the shown day, largest first (empty ones left out).
    private var breakdown: [(category: AppCategory, value: Double)] {
        var sums: [AppCategory: Double] = [:]
        for r in rows { sums[AppCategory.of(path: r.iconPath), default: 0] += value(r) }
        return AppCategory.allCases.compactMap { c in sums[c].flatMap { $0 > 0 ? (c, $0) : nil } }
            .sorted { $0.value > $1.value }
    }

    private var shownRows: [Row] {
        guard let filter else { return rows }
        return rows.filter { AppCategory.of(path: $0.iconPath) == filter }
    }

    /// "● Work 52%" per category, two columns; a tap filters the app list.
    private var categoryLegend: some View {
        let total = max(1e-9, breakdown.reduce(0) { $0 + $1.value })
        return LazyVGrid(columns: [GridItem(.fixed(112), spacing: 8, alignment: .leading),
                                   GridItem(.fixed(112), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 3) {
            ForEach(breakdown, id: \.category) { slice in
                let share = slice.value / total
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
                .help(filter == slice.category ? String(localized: "Show all apps") : String(localized: "Show only \(slice.category.name) apps"))
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

    private func row(_ app: Row) -> some View {
        let fraction = dayTotal > 0 ? value(app) / dayTotal : 0
        let screen = EnergyMonitor.label(app.screenJoules)
        let itself = EnergyMonitor.label(max(0, app.joules - app.screenJoules))
        let split = app.id == EnergyMonitor.systemKey
            ? String(localized: "Time away, the Mac asleep, and macOS itself")
            : String(localized: "The screen and the Mac while in front: \(screen) · the app itself: \(itself)")
        return VStack(spacing: 3) {
            HStack(spacing: 7) {
                Group {
                    if let path = app.iconPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                    } else if app.id == EnergyMonitor.systemKey {
                        Image(systemName: "apple.logo").resizable().scaledToFit()
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Image(systemName: "app.dashed").resizable()
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 16, height: 16)
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                // Both measures — "2h 10m · 7%" — the shown one brighter.
                HStack(spacing: 4) {
                    if app.seconds > 0 {
                        Text(formatDuration(app.seconds))
                            .foregroundStyle(.white.opacity(byEnergy ? 0.4 : 0.7))
                    }
                    if app.seconds > 0 && app.joules > 0 { Text(verbatim: "·").foregroundStyle(.white.opacity(0.3)) }
                    if app.joules > 0 {
                        Text(verbatim: EnergyMonitor.label(app.joules))
                            .foregroundStyle(byEnergy ? Color.coral : .white.opacity(0.4))
                            .help(split)
                    }
                }
                .font(.system(size: 11, weight: .medium))
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
    let slices: [(category: AppCategory, value: Double)]
    let highlighted: AppCategory?

    var body: some View {
        let total = max(1e-9, slices.reduce(0) { $0 + $1.value })
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
            let end = start + slice.value / total
            defer { start = end }
            return (slice.category, start, end)
        }
    }
}
