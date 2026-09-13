import Foundation

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
    var deletedAt: Date?      // non-nil means it's in the trash
}

/// Local to-do list with a trash that keeps deleted items for `retentionDays`.
/// (Sync with macOS Reminders is intentionally left out for now.)
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []      // active
    @Published private(set) var trash: [TodoItem] = []      // deleted, within retention

    let retentionDays = 7
    private var all: [TodoItem] = []

    init() {
        load()
        purgeExpired()
        refresh()
    }

    func add(_ title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        all.insert(TodoItem(title: text), at: 0)
        commit()
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
