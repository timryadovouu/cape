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
