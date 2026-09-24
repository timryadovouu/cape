import SwiftUI

struct BufferPanel: View {
    @ObservedObject var manager: BufferManager
    @ObservedObject var state: NotchState
    @ObservedObject var voice: VoiceDictation

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
                        ForEach(sections, id: \.title) { section in
                            sectionHeader(section.title)
                            ForEach(section.items) { item in
                                BufferRow(item: item,
                                          onFavorite: { manager.toggleFavorite(item) },
                                          onCopy: { manager.copyToPasteboard(item) },
                                          onDelete: { manager.delete(item) })
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                Button { voice.toggle() } label: {
                    Group {
                        switch voice.status {
                        case .downloading, .loading:
                            // Model downloading / loading — progress lives in Settings.
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        case .recording:
                            RecordingMic()
                        default:
                            Image(systemName: voiceIcon).font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(width: 40, height: 32)
                    .foregroundStyle(voiceTint)
                    .background(voiceTint.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .opacity(micEnabled ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!micEnabled)
                .help(voiceHelp)

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

            if voice.status == .idle && !voice.modelDownloaded {
                Text("Download the dictation model in Settings › Voice to dictate.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }

            GrabberBar(state: state)
        }
    }

    // MARK: - Day sections

    /// Pinned favorites first, then one group per calendar day (newest first —
    /// `recent` is already sorted that way).
    private var sections: [(title: String, items: [BufferItem])] {
        var out: [(title: String, items: [BufferItem])] = []
        let pinned = manager.recent.filter(\.isFavorite)
        if !pinned.isEmpty { out.append((Self.pinnedTitle, pinned)) }
        for item in manager.recent where !item.isFavorite {
            let title = Self.dayTitle(item.date)
            if out.last?.title == title { out[out.count - 1].items.append(item) }
            else { out.append((title, [item])) }
        }
        return out
    }

    private static let pinnedTitle = "Pinned"

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            if title == Self.pinnedTitle {
                Image(systemName: "star.fill").font(.system(size: 8))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
            }
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.top, 2)
    }

    /// "Today" / "Yesterday" / "Mon, 22 Sep".
    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, d MMM"; return f
    }()

    private var micEnabled: Bool {
        (voice.status == .idle && voice.modelDownloaded) || voice.status == .recording
    }

    private var voiceIcon: String {
        switch voice.status {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .downloading, .loading: return "arrow.down"
        }
    }

    private var voiceTint: Color {
        switch voice.status {
        case .idle: return .white.opacity(0.75)
        case .recording: return Color(red: 1, green: 0.4, blue: 0.4)
        case .transcribing, .downloading, .loading: return .coral
        }
    }

    private var voiceHelp: String {
        switch voice.status {
        case .idle: return voice.modelDownloaded
            ? "Dictate — speak, then it's transcribed onto the clipboard"
            : "Download the dictation model in Settings › Voice first"
        case .recording: return "Recording — tap to stop"
        case .transcribing: return "Transcribing…"
        case .downloading: return "Downloading model… \(Int(voice.downloadProgress * 100))%"
        case .loading: return "Loading model…"
        }
    }
}

/// The mic while recording: a gentle breathing pulse so it's obvious the app is
/// listening — clearer than a static icon.
private struct RecordingMic: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 13, weight: .semibold))
            .scaleEffect(pulse ? 1.15 : 0.9)
            .opacity(pulse ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
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
        let kind: String
        switch item.kind {
        case .text: kind = "Text"
        case .image: kind = "Image · \(item.name)"
        case .file: kind = item.url.pathExtension.uppercased().isEmpty
            ? "File" : item.url.pathExtension.uppercased()
        }
        return "\(Self.timeFormatter.string(from: item.date)) · \(kind)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
