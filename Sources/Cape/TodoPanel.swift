import SwiftUI
import AppKit

struct TodoPanel: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var state: NotchState
    @State private var draft = ""
    @State private var showTrash = false
    /// Task open in the card (text + reminder), floating over the list.
    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            header

            if showTrash {
                trashList
            } else {
                addField
                activeList
            }

            GrabberBar(state: state)
        }
        .overlay {
            if let id = editingID, let item = store.items.first(where: { $0.id == id }) {
                TaskCard(item: item, onSave: { title, due in
                    store.rename(item, title)
                    if due != item.due { store.setDue(item, due) }
                    closeEditor()
                }, onClose: closeEditor)
                .id(item.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { showTrash.toggle() } label: {
                Image(systemName: showTrash ? "list.bullet" : "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(showTrash ? "Back to tasks" : "Show trash")
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("New task… add a time: “в 15:00”, “через 20 мин”", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit(commit)
            Button(action: commit) {
                Text("Add")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func commit() {
        store.add(draft)
        draft = ""
    }

    // MARK: - Task card

    private func openEditor(_ item: TodoItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { editingID = item.id }
    }

    private func closeEditor() {
        withAnimation(.easeOut(duration: 0.15)) { editingID = nil }
    }

    private func copyTitle(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private var activeList: some View {
        Group {
            if store.items.isEmpty {
                Spacer()
                Text("No tasks — enjoy 🎉").font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                // Re-evaluated every minute so tasks slide into "Overdue" on time.
                TimelineView(.everyMinute) { context in
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(sections(now: context.date), id: \.title) { section in
                                if let title = section.title { sectionHeader(title, section.alert) }
                                ForEach(section.items) { item in
                                    TaskRow(item: item, now: context.date,
                                            onToggle: { store.toggle(item) },
                                            onCopy: { copyTitle(item.title) },
                                            onReminder: { openEditor(item) },
                                            onDelete: { store.delete(item) })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private struct TaskSection {
        let title: String?      // nil = no header (plain list)
        var alert = false       // tint the header (Overdue)
        let items: [TodoItem]
    }

    /// Overdue / Today / Upcoming / No date / Done — only when at least one task
    /// has a time; otherwise the plain list (undone on top) as before.
    private func sections(now: Date) -> [TaskSection] {
        let undone = store.items.filter { !$0.done }
        let done = store.items.filter(\.done)
        guard store.items.contains(where: { $0.due != nil }) else {
            return [TaskSection(title: nil, items: store.items)]
        }
        let cal = Calendar.current
        let dated = undone.filter { $0.due != nil }.sorted { $0.due! < $1.due! }
        let groups: [TaskSection] = [
            TaskSection(title: "Overdue", alert: true, items: dated.filter { $0.due! <= now }),
            TaskSection(title: "Today", items: dated.filter { $0.due! > now && cal.isDateInToday($0.due!) }),
            TaskSection(title: "Upcoming", items: dated.filter { $0.due! > now && !cal.isDateInToday($0.due!) }),
            TaskSection(title: "No date", items: undone.filter { $0.due == nil }),
            TaskSection(title: "Done", items: done),
        ]
        return groups.filter { !$0.items.isEmpty }
    }

    private func sectionHeader(_ title: String, _ alert: Bool) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(alert ? TaskRow.overdueColor.opacity(0.85) : .white.opacity(0.4))
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.top, 2)
    }

    private var trashList: some View {
        Group {
            if store.trash.isEmpty {
                Spacer()
                Text("Trash is empty").font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.trash) { item in
                            HStack(spacing: 8) {
                                Text(item.title).font(.system(size: 12))
                                    .strikethrough(item.done)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                                Spacer()
                                Button { store.restore(item) } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }.buttonStyle(.plain)
                                Button { store.purge(item) } label: {
                                    Image(systemName: "xmark")
                                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

}

private struct TaskRow: View {
    let item: TodoItem
    let now: Date
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onReminder: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    static let overdueColor = Color(red: 1, green: 0.45, blue: 0.45)

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Color(red: 0.3, green: 0.85, blue: 0.45) : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .white.opacity(0.4) : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let due = item.due {
                Button(action: onReminder) { dueChip(due) }
                    .buttonStyle(.plain)
                    .help("Edit the task and its reminder")
            }

            // Always laid out (only shown on hover) so the row height never jumps.
            HStack(spacing: 6) {
                rowButton(item.due == nil ? "bell" : "bell.fill",
                          help: item.due == nil ? "Set a reminder" : "Edit the task and its reminder",
                          action: onReminder)
                rowButton("doc.on.doc", help: "Copy", action: onCopy)
                rowButton("trash", help: "Delete", danger: true, action: onDelete)
            }
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .frame(height: 26)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(hovering ? 0.1 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }

    /// "🔔 15:00" — red once overdue, coral within the hour, muted otherwise.
    private func dueChip(_ due: Date) -> some View {
        let tint: Color = item.done ? .white.opacity(0.3)
            : due <= now ? Self.overdueColor
            : due.timeIntervalSince(now) < 3600 ? .coral
            : .white.opacity(0.55)
        return HStack(spacing: 3) {
            Image(systemName: "bell.fill").font(.system(size: 8))
            Text(Self.dueLabel(due, now: now))
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
        .fixedSize()
    }

    /// "15:00" today, "Tmrw 9:00", "Fri 9:00" this week, else "26 Sep 9:00".
    static func dueLabel(_ due: Date, now: Date) -> String {
        let cal = Calendar.current
        let time = timeFormatter.string(from: due)
        if cal.isDateInToday(due) { return time }
        if cal.isDateInTomorrow(due) { return "Tmrw \(time)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: due)).day ?? 99
        return (abs(days) < 7 ? weekdayFormatter : dateFormatter).string(from: due) + " \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private func rowButton(_ icon: String, help: String, danger: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(danger ? Color(red: 1, green: 0.5, blue: 0.5) : .white.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(danger ? Color.red.opacity(0.18) : Color.white.opacity(0.13))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The task card: edit the text and set the reminder with quick picks, a
/// calendar and a 24-hour time — floats over the task list inside the notch.
/// Enter saves, Esc closes.
private struct TaskCard: View {
    let item: TodoItem
    let onSave: (String, Date?) -> Void
    let onClose: () -> Void

    @State private var title: String
    @State private var date: Date
    @State private var remind: Bool

    init(item: TodoItem, onSave: @escaping (String, Date?) -> Void, onClose: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onClose = onClose
        _title = State(initialValue: item.title)
        // Start from the current time, else the next full hour.
        let nextHour = Calendar.current.date(bySetting: .minute, value: 0,
                                             of: Date().addingTimeInterval(3600)) ?? Date()
        _date = State(initialValue: item.due ?? nextHour)
        // Opened from the bell, so a new task starts with the reminder on.
        _remind = State(initialValue: true)
    }

    private var cal: Calendar { Calendar.current }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (!remind || date > Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist").font(.system(size: 10))
                        .foregroundStyle(Color.coral)
                    Text("Task").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }

                TextField("Task", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { if canSave { save() } }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Button { remind.toggle() } label: {
                    HStack(spacing: 7) {
                        CoralSwitch(isOn: remind)
                        Text("Remind me").font(.system(size: 11, weight: .medium))
                        Text(summary)
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(summaryColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 5) {
                    ForEach(quickPicks, id: \.0) { pick in
                        chip(pick.0, selected: remind && abs(date.timeIntervalSince(pick.1)) < 30) {
                            date = pick.1; remind = true
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("Time").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize()
                    Spacer()
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Color.coral.opacity(canSave ? 0.9 : 0.3))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .help(canSave ? "Save (Enter)" : "Pick a time in the future")
                }
            }
            .frame(maxWidth: .infinity)

            DatePicker("", selection: dayBinding, in: cal.startOfDay(for: Date())...,
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .fixedSize()
                .opacity(remind ? 1 : 0.4)
        }
        .environment(\.locale, Locale(identifier: "en_GB"))   // 24-hour clock, weeks from Monday
        .environment(\.colorScheme, .dark)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1))
        )
        .onExitCommand(perform: onClose)
    }

    private func save() {
        guard canSave else { return }
        onSave(title, remind ? date : nil)
    }

    // MARK: Date pieces

    /// The calendar changes the day and keeps the time; the stepper the reverse.
    private var dayBinding: Binding<Date> {
        Binding(get: { date }, set: { day in
            date = merge(day: day, time: date); remind = true
        })
    }
    private var timeBinding: Binding<Date> {
        Binding(get: { date }, set: { time in
            date = merge(day: date, time: time); remind = true
        })
    }
    private func merge(day: Date, time: Date) -> Date {
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private var quickPicks: [(String, Date)] {
        let now = Date()
        let start = cal.date(bySetting: .second, value: 0, of: now) ?? now
        var picks: [(String, Date)] = [("In 1 h", start.addingTimeInterval(3600))]
        if let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now), evening > now {
            picks.append(("18:00", evening))
        }
        if let tmrw = cal.date(byAdding: .day, value: 1, to: now),
           let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tmrw) {
            picks.append(("Tmrw 9:00", nine))
        }
        // Next Monday morning (a week ahead when today is Monday).
        if let monday = cal.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                                     matchingPolicy: .nextTime) {
            picks.append(("Mon 9:00", monday))
        }
        return picks
    }

    private var summary: String {
        guard remind else { return item.due == nil ? "" : "Off — removes it" }
        let now = Date()
        if date <= now { return "In the past" }
        let label = TaskRow.dueLabel(date, now: now)
        return cal.isDateInToday(date) ? "Today \(label)" : label
    }
    private var summaryColor: Color {
        !remind ? .white.opacity(0.45) : date <= Date() ? TaskRow.overdueColor : .coral
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(selected ? Color.coral : .white)
                .background(selected ? Color.coral.opacity(0.18) : Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
