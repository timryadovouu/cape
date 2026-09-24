import SwiftUI
import AppKit

struct TodoPanel: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var state: NotchState
    @State private var draft = ""
    @State private var showTrash = false
    /// Task whose reminder is being set — its editor replaces the add field.
    @State private var editingID: UUID?
    @State private var pickDate = Date()

    var body: some View {
        VStack(spacing: 8) {
            header

            if showTrash {
                trashList
            } else {
                if let id = editingID, let item = store.items.first(where: { $0.id == id }) {
                    reminderEditor(item)
                } else {
                    addField
                }
                activeList
            }

            GrabberBar(state: state)
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

    // MARK: - Reminder editor

    private func openEditor(_ item: TodoItem) {
        // Start from the current time, else the next full hour.
        let cal = Calendar.current
        let nextHour = cal.date(bySetting: .minute, value: 0, of: Date().addingTimeInterval(3600)) ?? Date()
        pickDate = item.due ?? nextHour
        editingID = item.id
    }

    private func setDue(_ item: TodoItem, _ date: Date?) {
        store.setDue(item, date)
        editingID = nil
    }

    /// Quick picks + a 24-hour date & time field, in place of the add field.
    private func reminderEditor(_ item: TodoItem) -> some View {
        let cal = Calendar.current
        let now = Date()
        let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                 of: cal.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(Color.coral)
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { editingID = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
            HStack(spacing: 6) {
                quickPick("+1 h") { setDue(item, now.addingTimeInterval(3600)) }
                if evening > now { quickPick("18:00") { setDue(item, evening) } }
                quickPick("Tmrw 9:00") { setDue(item, tomorrow9) }
                Spacer(minLength: 4)
                DatePicker("", selection: $pickDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .environment(\.locale, Locale(identifier: "en_GB"))   // 24-hour clock
                    .environment(\.colorScheme, .dark)
                    .fixedSize()
                Button { setDue(item, pickDate) } label: {
                    Text("Set")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.coral.opacity(pickDate > now ? 0.9 : 0.3))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(pickDate <= now)
                .help(pickDate > now ? "Remind at this time" : "Pick a time in the future")
                if item.due != nil {
                    Button { setDue(item, nil) } label: {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TaskRow.overdueColor)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the reminder")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.coral.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func quickPick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    .help("Change or remove the reminder")
            }

            // Always laid out (only shown on hover) so the row height never jumps.
            HStack(spacing: 6) {
                rowButton(item.due == nil ? "bell" : "bell.fill",
                          help: item.due == nil ? "Set a reminder" : "Change or remove the reminder",
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
