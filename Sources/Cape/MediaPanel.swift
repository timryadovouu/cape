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
                Spacer()
                VStack(spacing: 4) {
                    Text(media.title.isEmpty ? "—" : media.title)
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(media.artist)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(media.source.rawValue.capitalized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35)).padding(.top, 2)
                }
                HStack(spacing: 26) {
                    controlButton("backward.fill", size: 18, action: media.previous)
                    controlButton(media.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                                  size: 44, action: media.playPause)
                    controlButton("forward.fill", size: 18, action: media.next)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
