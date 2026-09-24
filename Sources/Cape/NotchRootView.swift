import SwiftUI

/// Root view: the "brow" that lives over the physical notch and expands on
/// hover, Dynamic-Island style.
struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var pomodoro: PomodoroModel
    @ObservedObject var media: MediaController
    @ObservedObject var claude: ClaudeSessionsManager
    @ObservedObject var settings: Settings
    @ObservedObject var todo: TodoStore
    let modules: AppModules
    let metrics: NotchMetrics

    @State private var playFlash = false   // brief play glyph when playback resumes

    // Expanded panel size.
    static let panelWidth: CGFloat = 560
    static let panelHeight: CGFloat = 272
    static let panelHeightTall: CGFloat = 430
    static func expandedHeight(_ tall: Bool) -> CGFloat { tall ? panelHeightTall : panelHeight }

    static let timerPillWidth: CGFloat = 70
    static let pomodoroControlsWidth: CGFloat = 94   // inline pause / next / cancel strip
    static let mediaIslandWidth: CGFloat = 40        // equalizer / pause glyph, left of the camera
    private let timerPillW = NotchRootView.timerPillWidth
    private let buttonsW = NotchRootView.pomodoroControlsWidth
    private let eqW = NotchRootView.mediaIslandWidth
    private let claudeW: CGFloat = 20   // small coral island; the pulsing dot sits centered
    // The window is shifted up by this much (see NotchController); the island is
    // grown upward by the same amount so black covers the very top rows with no
    // thin gap, while everything below stays put.
    static let topOvershoot: CGFloat = 3

    private var notchW: CGFloat { metrics.notchWidth }
    private var notchH: CGFloat { metrics.notchHeight }
    /// A pomodoro session exists (running or paused) — the collapsed pill stays up.
    private var timerActive: Bool { !state.expanded && pomodoro.isActive }
    private var playing: Bool { media.isPlaying }
    /// A track is loaded but paused.
    private var paused: Bool { !state.expanded && media.source != .none && !media.isPlaying }

    private var rightExt: CGFloat {
        guard timerActive else { return 0 }
        return timerPillW + (state.pomodoroControls ? buttonsW : 0)
    }

    /// Coral "Claude is thinking" island, shown while ≥1 session is working.
    private var showClaude: Bool { !state.expanded && settings.trackClaude && claude.anyWorking }
    private var claudeExt: CGFloat { showClaude ? claudeW : 0 }

    /// Task reminder that came due — outermost on the right until looked at.
    private var showReminder: Bool { !state.expanded && !todo.ringing.isEmpty }
    private var reminderText: String { Self.reminderText(todo.ringing) }
    private var reminderExt: CGFloat { showReminder ? Self.reminderWidth(reminderText) : 0 }

    /// "Call mom" / "Call mom +2" — the first ringing task, trimmed.
    static func reminderText(_ ringing: [TodoItem]) -> String {
        guard let first = ringing.first else { return "" }
        let title = first.title.count > 24 ? String(first.title.prefix(23)) + "…" : first.title
        return ringing.count > 1 ? "\(title) +\(ringing.count - 1)" : title
    }
    static func reminderWidth(_ text: String) -> CGFloat {
        min(230, 40 + CGFloat(text.count) * 6.6)
    }

    /// Left extension shows either a transient alert or a music equalizer.
    private var leftExt: CGFloat {
        guard !state.expanded else { return 0 }
        if let alert = state.alert {
            if alert.battery != nil { return 96 }
            return alert.text == nil ? 46 : 50 + CGFloat(alert.text?.count ?? 0) * 7.5
        }
        if playing || paused { return eqW }   // same width so ⏯ doesn't shift the notch
        return 0
    }

    private var islandW: CGFloat {
        // Collapsed, a side with no island ends exactly at the cutout's edge (the
        // window is centered on the physical notch — see NotchMetrics.centerX).
        state.expanded ? Self.panelWidth : notchW + leftExt + claudeExt + rightExt + reminderExt
    }
    private var islandH: CGFloat { (state.expanded ? Self.expandedHeight(state.tall) : notchH) + Self.topOvershoot }
    private var radius: CGFloat { state.expanded ? 28 : min(13, notchH / 2) }
    // Shift the center so the middle (notch) portion stays over the camera.
    private var centerShift: CGFloat { state.expanded ? 0 : (claudeExt + rightExt + reminderExt - leftExt) / 2 }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            // The black shape — the only thing that morphs between brow and panel.
            // With a side island (music, timer, Claude…) the brow sits off-center,
            // so the shape also travels sideways to the centered panel.
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: radius, bottomTrailing: radius),
                                   style: .continuous)
                .fill(Color.black)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: radius, bottomTrailing: radius),
                                           style: .continuous)
                        .strokeBorder(Color.white.opacity(state.expanded ? 0.09 : 0), lineWidth: 1)
                )
                .shadow(color: .black.opacity(state.expanded ? 0.55 : 0), radius: 16, y: 8)
                .frame(width: islandW, height: islandH)
                .offset(x: centerShift)
            // The content is a separate layer laid out in its *final* place, so it
            // never rides along with that sideways travel.
            content
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: state.expanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.alert)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: pomodoro.isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: state.pomodoroControls)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: playing)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: paused)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: showClaude)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: reminderText)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: state.tall)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Fill into the notch/menu-bar safe area so no thin gap shows at the top.
        .ignoresSafeArea(.all)
        .onChange(of: playing) { isPlaying in
            if isPlaying {
                playFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { playFlash = false }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if state.expanded {
            ExpandedPanel(state: state, settings: modules.settings, system: modules.system,
                          updater: modules.updater, modules: modules, notchWidth: notchW,
                          topInset: notchH + Self.topOvershoot)
                .frame(width: Self.panelWidth, height: islandH, alignment: .top)
                .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28),
                                                  style: .continuous))
                .transition(Self.panelSwap)
        } else {
            collapsed
                .frame(width: islandW, height: islandH, alignment: .top)
                .offset(x: centerShift)
                .transition(Self.browSwap)
        }
    }

    /// The panel fades in a beat late — once the shape has grown under it, so no
    /// text shows past its edge — and vanishes at once when closing.
    private static let panelSwap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.1)),
        removal: .opacity.animation(.easeIn(duration: 0.06))
    )
    /// The brow's islands (⏸, timer, …) are back immediately on close.
    private static let browSwap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.12)),
        removal: .opacity.animation(.easeIn(duration: 0.06))
    )

    private var collapsed: some View {
        HStack(spacing: 0) {
            // Left extension — alert, or music equalizer while playing.
            ZStack {
                if let alert = state.alert, let level = alert.battery {
                    ChargingBadge(level: level)
                        .transition(.scale.combined(with: .opacity))
                } else if let alert = state.alert {
                    HStack(spacing: 5) {
                        Image(systemName: alert.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(alert.color)
                        if let text = alert.text {
                            Text(text)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize()
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if playing {
                    if playFlash {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.980, green: 0.514, blue: 0.302))
                    } else {
                        EqualizerBars(color: Color(red: 0.35, green: 0.85, blue: 0.45))
                            .transition(.opacity)
                    }
                } else if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.980, green: 0.514, blue: 0.302))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: leftExt)

            // Center — camera area, drawn empty.
            Color.clear.frame(width: notchW)

            // Claude island (coral) — inner to the timer, shown while a session thinks.
            ZStack {
                if showClaude {
                    ClaudeBlob()
                        .frame(width: 11, height: 11)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: claudeExt)

            // Right extension — countdown pill, plus inline controls on hover.
            ZStack {
                if pomodoro.isActive {
                    HStack(spacing: 6) {
                        pomodoroTime
                        if state.pomodoroControls {
                            pomodoroButtons
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: rightExt)

            // Reminder — outermost on the right, until hovered.
            ZStack {
                if showReminder {
                    HStack(spacing: 5) {
                        RingingBell()
                        Text(reminderText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 6)
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .frame(width: reminderExt)
        }
        .frame(height: notchH)
        .padding(.top, Self.topOvershoot)   // keep content below the extended black top
    }

    /// Collapsed countdown. Blinks gently while paused so it's clear the timer is
    /// on hold (not counting down).
    private var pomodoroTime: some View {
        TimelineView(.animation(paused: pomodoro.isRunning)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let blink = pomodoro.isRunning ? 1.0 : 0.45 + 0.45 * (0.5 + 0.5 * sin(t * 3.2))
            Text(formatTime(pomodoro.timeRemaining))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor(pomodoro.phase))
                .opacity(blink)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture { pomodoro.toggle() }   // click the time itself to pause / resume
    }

    private var pomodoroButtons: some View {
        HStack(spacing: 4) {
            pomoButton(pomodoro.isRunning ? "pause.fill" : "play.fill") { pomodoro.toggle() }
            pomoButton("forward.fill") { pomodoro.skip() }
            pomoButton("xmark") { pomodoro.cancel() }
        }
    }

    private func pomoButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 20)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Three pulsing bars, like the Dynamic Island "now playing" indicator.
struct EqualizerBars: View {
    var color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height(t, i))
                }
            }
            .frame(height: 16)
        }
    }

    private func height(_ t: Double, _ i: Int) -> CGFloat {
        // Two sines with an irrational frequency ratio → long, organic, non-cyclic.
        let p = Double(i)
        let v = 0.5 + 0.30 * sin(t * 5.3 + p * 2.1) + 0.20 * sin(t * 9.7 + p * 4.3)
        return 4 + min(1, max(0, v)) * 12
    }
}

/// Charger-connected flash: the bolt springs in with a pulsing coral glow, a
/// mini battery fills up to the current level, then the percent fades in.
struct ChargingBadge: View {
    let level: Double   // 0…1

    @State private var boltIn = false
    @State private var glow = false
    @State private var fill = 0.0
    @State private var textIn = false

    private let bodyW: CGFloat = 22, bodyH: CGFloat = 11, inset: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.coral)
                .shadow(color: Color.coral.opacity(glow ? 0.95 : 0.2), radius: glow ? 5 : 1)
                .scaleEffect(boltIn ? 1 : 0.2)
                .rotationEffect(.degrees(boltIn ? 0 : -25))

            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.coral)
                        .frame(width: max(0, (bodyW - inset * 2) * fill), height: bodyH - inset * 2)
                        .padding(.leading, inset)
                }
                .frame(width: bodyW, height: bodyH)
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 1.5, height: 4)
            }

            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
                .opacity(textIn ? 1 : 0)
                .offset(x: textIn ? 0 : -4)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.45)) { boltIn = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { fill = level }
            withAnimation(.easeOut(duration: 0.3).delay(0.55)) { textIn = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(0.3)) { glow = true }
        }
    }
}

/// Coral bell that rings in short bursts (a quick wiggle every ~2.4 s) — the
/// task-reminder glyph beside the brow.
struct RingingBell: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: 2.4)
            let envelope = phase < 0.7 ? 1 - phase / 0.7 : 0
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.coral)
                .rotationEffect(.degrees(envelope * 18 * sin(t * 30)), anchor: .top)
                .shadow(color: Color.coral.opacity(0.6 * envelope), radius: 4)
        }
    }
}

/// Small pulsing coral "blob" shown while a Claude session is thinking.
struct ClaudeBlob: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let p = 0.5 + 0.5 * sin(t * 3.0)   // 0...1
            Circle()
                .fill(Color(red: 0.980, green: 0.514, blue: 0.302))
                .scaleEffect(0.7 + 0.3 * p)
                .opacity(0.6 + 0.4 * p)
        }
    }
}
