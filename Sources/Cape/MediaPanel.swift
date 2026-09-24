import SwiftUI

struct MediaPanel: View {
    @ObservedObject var media: MediaController

    var body: some View {
        VStack(spacing: 16) {
            if media.source == .none {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Nothing playing")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    Text("Open Spotify or cmus")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
            } else {
                HStack(spacing: 16) {
                    artwork
                    // Centered column: track info sits just above the progress bar,
                    // on the same axis as the play button.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 2) {
                            Text(media.title.isEmpty ? "—" : media.title)
                                .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(media.artist)
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            Text(media.source.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35)).padding(.top, 1)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                        if media.duration > 0 {
                            ProgressScrubber(media: media)
                        }
                        HStack(spacing: 26) {
                            controlButton("backward.fill", size: 16, action: media.previous)
                            controlButton(media.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                                          size: 36, action: media.playPause)
                            controlButton("forward.fill", size: 16, action: media.next)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Cover art (Spotify's, or the album folder's / embedded one for cmus); a
    /// music-note tile when there is none.
    private var artwork: some View {
        let size: CGFloat = 118
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08))
            Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.25))
            if let image = media.artwork {
                Image(nsImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Coral progress bar with elapsed / remaining time. Click or drag to seek; the
/// position is extrapolated every frame between polls so it glides while playing.
/// Click the right-hand time to switch between "−remaining" and the track length.
private struct ProgressScrubber: View {
    @ObservedObject var media: MediaController
    @State private var dragFraction: Double?     // while scrubbing
    @State private var hovering = false
    @AppStorage("mediaShowTotalTime") private var showTotal = false

    private let knob: CGFloat = 14

    var body: some View {
        TimelineView(.animation(paused: !media.isPlaying && dragFraction == nil)) { context in
            let fraction = dragFraction ?? liveFraction(at: context.date)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let active = hovering || dragFraction != nil
                    let track: CGFloat = active ? 6 : 4
                    // Track and knob are sized independently and both centered, so
                    // the bar never shifts when it thickens on hover.
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                            .frame(height: track)
                        Capsule()
                            .fill(LinearGradient(colors: [Color.coral.opacity(0.75), Color.coral],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, w * fraction), height: track)
                        Circle()
                            .fill(Color.coral)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                            .frame(width: knob, height: knob)
                            .shadow(color: Color.coral.opacity(0.7), radius: 4)
                            .offset(x: min(max(0, w * fraction - knob / 2), w - knob))
                            .opacity(active ? 1 : 0)
                            .scaleEffect(active ? 1 : 0.4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in dragFraction = min(1, max(0, g.location.x / w)) }
                        .onEnded { g in
                            media.seek(to: min(1, max(0, g.location.x / w)) * media.duration)
                            dragFraction = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: active)
                }
                .frame(height: knob)
                .onHover { hovering = $0 }

                HStack {
                    Text(Self.clock(fraction * media.duration))
                    Spacer()
                    Text(showTotal ? Self.clock(media.duration)
                                   : "-" + Self.clock(media.duration * (1 - fraction)))
                        .contentShape(Rectangle())
                        .onTapGesture { showTotal.toggle() }
                        .help(showTotal ? "Track length — click for time left" : "Time left — click for track length")
                }
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func liveFraction(at now: Date) -> Double {
        guard media.duration > 0 else { return 0 }
        let elapsed = media.isPlaying ? now.timeIntervalSince(media.positionDate) : 0
        return min(1, max(0, (media.position + elapsed) / media.duration))
    }

    /// "3:21" / "1:02:05".
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
