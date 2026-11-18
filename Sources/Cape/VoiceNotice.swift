import SwiftUI

/// The strip that drops down from the brow when dictation is asked for without
/// a model: "Dictation needs a model" with a ⬇ button, then the download, the
/// first-time preparation (the model is compiled for the Neural Engine — the
/// wait after a download), and "Ready". Messages longer than a word hang under
/// the brow like this (see also `ShellDoneStrip`); the short flashes stay on
/// the left.
struct VoiceNoticePanel: View {
    enum Phase: Equatable { case needsModel, downloading(Double), preparing, ready }

    @ObservedObject var voice: VoiceDictation
    @ObservedObject var state: NotchState
    /// The ✕ goes here when the island right of the camera is taken (Claude).
    var closeInStrip = false

    static let height: CGFloat = 46

    private var phase: Phase {
        if let demo = state.voiceNoticeDemo { return demo }
        switch voice.status {
        case .downloading: return .downloading(voice.downloadProgress)
        case .loading: return .preparing
        default: return state.voiceNoticeReady ? .ready : .needsModel
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            glyph.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if case .downloading(let fraction) = phase {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.coral).frame(width: max(3, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 6)
            if phase == .needsModel {
                Button { voice.prepareModel() } label: { TrafficButton(symbol: "arrow.down") }
                    .buttonStyle(.plain)
                    .help("Download the dictation model")
            }
            if closeInStrip { VoiceNoticeClose(state: state, voice: voice) }
        }
        // Right edge 10 pt in: the ⬇ sits exactly under the ✕ in the island above.
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private var title: String {
        switch phase {
        case .needsModel: return String(localized: "Dictation needs a model")
        case .downloading(let fraction): return String(localized: "Downloading the model… \(Int(fraction * 100))%")
        case .preparing: return String(localized: "Preparing the model…")
        case .ready: return String(localized: "Ready — dictate away")
        }
    }

    @ViewBuilder private var glyph: some View {
        switch phase {
        case .needsModel, .downloading:
            Image(systemName: "mic.fill").font(.system(size: 13)).foregroundStyle(Color.capeRed)
        case .preparing:
            Spinner()
        case .ready:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
        }
    }
}

/// ✕ — put the dictation strip away; while the model downloads, it cancels the
/// download too.
struct VoiceNoticeClose: View {
    @ObservedObject var state: NotchState
    @ObservedObject var voice: VoiceDictation

    var body: some View {
        Button {
            if voice.status == .downloading { voice.cancelDownload() }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) { state.voiceNotice = false }
        } label: {
            TrafficButton(symbol: "xmark")
        }
        .buttonStyle(.plain)
        .help(voice.status == .downloading ? String(localized: "Cancel the download") : String(localized: "Close"))
    }
}

/// A round red button like the window "traffic lights": a dark glyph inside.
private struct TrafficButton: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.black.opacity(0.6))
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.capeRed))
    }
}

/// A terminal command finished — `; cape done`, or any long one: ✓ / ✗, the
/// command (shortened in the middle) and how long it took, dropped down from
/// the brow like the dictation strip. A click brings its terminal to the front.
struct ShellDoneStrip: View {
    let done: ShellDone
    var onTap: () -> Void

    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: done.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(done.ok ? Color(red: 0.3, green: 0.85, blue: 0.45) : Color.capeRed)
            Text(verbatim: command)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if done.seconds > 0 {
                Text(verbatim: time)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var command: String {
        if !done.command.isEmpty { return done.command }
        return done.ok ? String(localized: "Done") : String(localized: "Failed")
    }

    private var time: String {
        (60..<3600).contains(done.seconds) ? String(localized: "\(done.seconds / 60)m \(done.seconds % 60)s")
            : formatDuration(done.seconds)
    }
}

/// A task came due: the ringing bell, its title (+N when several ring) and its
/// time, dropped down from the brow like `cape done`. Hovered, the time gives
/// way to ✓ (done) and ⏰ (ring again in a few minutes); a click elsewhere on it
/// just puts it away (the tasks stay, under Overdue). Both buttons act on the
/// first ringing task — the next slides in.
struct ReminderStrip: View {
    let ringing: [TodoItem]
    let hovered: Bool
    let snoozeMinutes: Int
    var onDone: () -> Void
    var onSnooze: () -> Void
    var onDismiss: () -> Void

    static let height: CGFloat = 34

    private var first: TodoItem? { ringing.first }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                RingingBell()
                Text(verbatim: first?.title ?? "")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(first?.id)
                    .transition(.opacity)
                if ringing.count > 1 {
                    Text(verbatim: "+\(ringing.count - 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize()
                }
                Spacer(minLength: 6)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            if hovered {
                HStack(spacing: 4) {
                    StripButton(symbol: "checkmark", tint: Color(red: 0.3, green: 0.85, blue: 0.45), action: onDone)
                        .help(Text("Done"))
                    StripButton(symbol: "alarm.fill", tint: .white, action: onSnooze)
                        .help(Text("Remind me in \(snoozeMinutes) min"))
                }
                .transition(.opacity)
            } else if let due = first?.due {
                Text(verbatim: Self.timeLabel(due))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, hovered ? 7 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovered)
        .animation(.easeOut(duration: 0.2), value: first?.id)
    }

    /// "15:00" today, "18 Nov, 15:00" for an older one that rang at launch.
    static func timeLabel(_ due: Date) -> String {
        Calendar.current.isDateInToday(due)
            ? due.formatted(date: .omitted, time: .shortened)
            : due.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

/// A small rounded button on a strip — like the timer's inline controls.
private struct StripButton: View {
    let symbol: String
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 22)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Get my IP: the flag and the country, the public IPv4 on the right — dropped
/// down from the brow like `cape done`. A click copies the IP (the coral clip
/// flashes on the left).
struct IPStrip: View {
    let info: NotchState.MyIP
    var onTap: () -> Void

    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            switch info {
            case .loading:
                Spinner().frame(width: 14, height: 14)
                Text("Checking your IP…").font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
            case .failed:
                Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.capeRed)
                Text("No connection").font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
            case .found(let r):
                Text(verbatim: r.flag ?? "🌐").font(.system(size: 15))
                Text(verbatim: r.country ?? String(localized: "Unknown country"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: r.ip)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
