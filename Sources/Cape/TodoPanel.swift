import SwiftUI
import AppKit

struct TodoPanel: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var state: NotchState
    @State private var draft = ""
    @State private var showTrash = false

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
            TextField("New task…", text: $draft)
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
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.items) { item in
                            TaskRow(item: item,
                                    onToggle: { store.toggle(item) },
                                    onCopy: { copyTitle(item.title) },
                                    onDelete: { store.delete(item) })
                        }
                    }
                }
            }
        }
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
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

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

            // Always laid out (only shown on hover) so the row height never jumps.
            HStack(spacing: 6) {
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
