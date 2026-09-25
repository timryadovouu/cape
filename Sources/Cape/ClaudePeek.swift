import SwiftUI

/// The list that drops down from the Claude island on hover: every Claude Code
/// session with what it's doing, and Allow / Deny for a tool waiting for you.
/// A light version of the notch — exactly as wide as the brow from its left end
/// to the Claude island (so it can be narrow: text truncates, buttons stay).
struct ClaudePeekPanel: View {
    @ObservedObject var claude: ClaudeSessionsManager

    static let maxRows = 5
    private static let rowH: CGFloat = 34
    private static let requestH: CGFloat = 64
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8

    /// Height for the current sessions + requests (the controller's hover zone
    /// uses the same number).
    static func height(sessions: [ClaudeSession], permissions: [ClaudePermission]) -> CGFloat {
        let shown = Array(sessions.prefix(maxRows))
        let requests = permissions.filter { p in shown.contains { $0.id == p.sessionID } }.count
        let items = shown.count + requests
        guard items > 0 else { return 0 }
        return padding * 2 + CGFloat(shown.count) * rowH + CGFloat(requests) * requestH
            + CGFloat(items - 1) * spacing
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(claude.sessions.prefix(Self.maxRows)) { session in
                SessionRow(session: session) { claude.focus(session) }
                    .frame(height: Self.rowH)
                ForEach(claude.permissions.filter { $0.sessionID == session.id }) { request in
                    RequestCard(request: request, claude: claude)
                        .frame(height: Self.requestH)
                }
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                StatusGlyph(status: session.status)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title ?? session.project)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if let prompt = session.prompt, !prompt.isEmpty {
                        Text(prompt)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text(label(now: tl.date))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(session.needsYou ? ClaudeBlob.amber : .white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 9)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(hovering ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.app == DesktopSessions.bundleID ? "Open this session in the Claude app"
              : "Bring its terminal to the front")
    }

    private func label(now: Date) -> String {
        let ago = ClaudePeekFormat.duration(now.timeIntervalSince(session.since))
        switch session.status {
        case .working: return ago
        case .permission: return "needs you"
        case .asking: return "asks you"
        case .waiting: return "waiting · \(ago)"
        case .done: return "done · \(ago) ago"
        }
    }
}

/// Allow / Deny for one tool call, with the time left before it goes back to
/// the terminal / app.
private struct RequestCard: View {
    let request: ClaudePermission
    let claude: ClaudeSessionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(request.tool)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ClaudeBlob.amber)
                Text(request.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text("\(max(0, Int(request.expires.timeIntervalSince(tl.date))))s")
                        .font(.system(size: 9, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            HStack(spacing: 6) {
                Button { claude.answer(request, allow: nil) } label: {
                    Text("Answer there")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .underline()
                }
                .buttonStyle(.plain)
                .help("Leave this to the terminal / Claude app")
                Spacer()
                pill("Deny", fill: Color.white.opacity(0.14)) { claude.answer(request, allow: false) }
                pill("Allow", fill: Color.coral) { claude.answer(request, allow: true) }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(ClaudeBlob.amber.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(ClaudeBlob.amber.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pill(_ title: String, fill: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(fill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Spinner while working, amber dot / question mark when it needs you, ✓ when done.
private struct StatusGlyph: View {
    let status: ClaudeSession.Status

    var body: some View {
        switch status {
        case .working:
            TimelineView(.animation) { tl in
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate * 360))
                    .padding(1)
            }
        case .permission, .waiting:
            ClaudeBlob(attention: true)
        case .asking:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(ClaudeBlob.amber)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
        }
    }
}

enum ClaudePeekFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
