import SwiftUI

/// iPhone-style home-indicator pill: tap to grow / shrink the panel height.
/// Shared by the Tasks and Clipboard panels.
struct GrabberBar: View {
    @ObservedObject var state: NotchState

    var body: some View {
        Button {
            state.holdOpen(2)          // keep open ~2s so shrinking doesn't insta-close
            state.tall.toggle()
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.tall ? "Shrink panel" : "Grow panel")
    }
}
