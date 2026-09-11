import SwiftUI

struct BufferPanel: View {
    @ObservedObject var manager: BufferManager
    @ObservedObject var state: NotchState

    var body: some View {
        VStack(spacing: 8) {
            if manager.recent.isEmpty {
                Spacer()
                Text("Copy anything —\nit shows up here")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.recent) { item in
                            BufferRow(item: item,
                                      onFavorite: { manager.toggleFavorite(item) },
                                      onCopy: { manager.copyToPasteboard(item) },
                                      onDelete: { manager.delete(item) })
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                Button(action: manager.openInFinder) {
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open the buffer folder to browse any date")

                Button(action: manager.clearToday) {
                    Label("Clear day", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.22))
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Delete today's whole buffer")
            }

            GrabberBar(state: state)
        }
    }
}

/// One row: thumbnail + name. Hover reveals copy / delete buttons; drag to move
/// the file out.
private struct BufferRow: View {
    let item: BufferItem
    let onFavorite: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    private static let gold = Color(red: 1.0, green: 0.78, blue: 0.28)

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                HStack(spacing: 6) {
                    rowButton(item.isFavorite ? "star.fill" : "star",
                              help: item.isFavorite ? "Unfavorite" : "Favorite — keep it, pinned on top",
                              gold: item.isFavorite, action: onFavorite)
                    rowButton("doc.on.doc", help: "Copy", action: onCopy)
                    rowButton("trash", help: "Delete", danger: true, action: onDelete)
                }
            } else if item.isFavorite {
                // At rest, still show which items are starred.
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Self.gold)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(hovering ? 0.13 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)                       // click body = copy back
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() } // drag out
        .onHover { hovering = $0 }
        .help("Click to copy · drag to move the file out")
    }

    private func rowButton(_ icon: String, help: String, danger: Bool = false,
                           gold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(gold ? Self.gold
                                 : danger ? Color(red: 1, green: 0.5, blue: 0.5)
                                 : .white.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(gold ? Self.gold.opacity(0.18)
                              : danger ? Color.red.opacity(0.18)
                              : Color.white.opacity(0.13))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let img = NSImage(contentsOf: item.url) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                icon
            }
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().scaledToFit()
        case .text:
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var icon: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable().scaledToFit()
    }

    private var title: String {
        switch item.kind {
        case .text:
            let s = (try? String(contentsOf: item.url, encoding: .utf8)) ?? item.name
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return item.name
        }
    }

    private var subtitle: String {
        switch item.kind {
        case .text: return "Text"
        case .image: return "Image · \(item.name)"
        case .file: return item.url.pathExtension.uppercased().isEmpty
            ? "File" : item.url.pathExtension.uppercased()
        }
    }
}
