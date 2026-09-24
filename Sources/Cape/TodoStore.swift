import Foundation

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
    var deletedAt: Date?      // non-nil means it's in the trash
    var due: Date?            // reminder time, parsed from the text ("в 15:00")
    var remindedAt: Date?     // set once the reminder has fired
}

/// Local to-do list with a trash that keeps deleted items for `retentionDays`,
/// and time reminders: a task whose text carries a time ("позвонить в 15:00",
/// "через 20 минут", "at 3pm") rings in the notch when it comes due.
/// (Sync with macOS Reminders is intentionally left out for now.)
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []      // active
    @Published private(set) var trash: [TodoItem] = []      // deleted, within retention
    /// Reminders that fired and haven't been looked at yet (shown beside the brow).
    @Published private(set) var ringing: [TodoItem] = []

    /// Called with the tasks that just came due (for the reminder sound).
    var onReminder: (([TodoItem]) -> Void)?

    let retentionDays = 7
    private var all: [TodoItem] = []
    private var ringingIDs: [UUID] = []
    private var timer: Timer?

    init() {
        load()
        purgeExpired()
        refresh()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.checkDue() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func add(_ title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let parsed = DueParser.parse(text) {
            all.insert(TodoItem(title: parsed.title, due: parsed.due), at: 0)
        } else {
            all.insert(TodoItem(title: text), at: 0)
        }
        commit()
    }

    /// Set, change (re-arms the reminder) or remove (`nil`) a task's time.
    func setDue(_ item: TodoItem, _ date: Date?) {
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { return }
        all[i].due = date
        all[i].remindedAt = nil
        ringingIDs.removeAll { $0 == item.id }
        commit()
    }

    /// The user has seen the ringing reminders (hovered them / opened Tasks).
    func dismissRinging() {
        guard !ringingIDs.isEmpty else { return }
        ringingIDs = []
        refresh()
    }

    /// Fire reminders whose time has come. Tasks that came due while the app
    /// was closed ring once on the next launch.
    private func checkDue() {
        let now = Date()
        var fired: [TodoItem] = []
        for i in all.indices where all[i].deletedAt == nil && !all[i].done && all[i].remindedAt == nil {
            if let due = all[i].due, due <= now {
                all[i].remindedAt = now
                fired.append(all[i])
            }
        }
        guard !fired.isEmpty else { return }
        ringingIDs.append(contentsOf: fired.map(\.id))
        commit()
        onReminder?(fired)
    }

    func toggle(_ item: TodoItem) {
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { return }
        all[i].done.toggle()
        commit()
    }

    /// Move to trash.
    func delete(_ item: TodoItem) {
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { return }
        all[i].deletedAt = Date()
        commit()
    }

    /// Restore from trash.
    func restore(_ item: TodoItem) {
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { return }
        all[i].deletedAt = nil
        commit()
    }

    /// Permanently remove one trashed item.
    func purge(_ item: TodoItem) {
        all.removeAll { $0.id == item.id }
        commit()
    }

    func emptyTrash() {
        all.removeAll { $0.deletedAt != nil }
        commit()
    }

    // MARK: - Internals

    private func purgeExpired() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        all.removeAll { ($0.deletedAt ?? Date.distantFuture) < cutoff }
    }

    private func commit() {
        save()
        refresh()
    }

    private func refresh() {
        // Undone tasks on top, completed ones sink to the bottom (order within
        // each group preserved).
        let active = all.filter { $0.deletedAt == nil }
        items = active.filter { !$0.done } + active.filter { $0.done }
        trash = all.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        // A reminder stops ringing once its task is done or deleted.
        ringingIDs = ringingIDs.filter { id in active.contains { $0.id == id && !$0.done } }
        ringing = ringingIDs.compactMap { id in active.first { $0.id == id } }
    }

    private var fileURL: URL {
        AppModules.supportDirectory.appendingPathComponent("todos.json")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: fileURL) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        all = decoded
    }
}
