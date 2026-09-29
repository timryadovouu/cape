import SwiftUI

/// Clawd, Claude Code's little critter, in coral pixels — sits in the Claude
/// island when a session finished while you were away. Hops in with a wave,
/// then every few seconds waves, stomps, blinks or hops — "done here, come
/// look" — so a glance at the notch catches it. Still in lists and drawings.
///
/// Around that: he looks toward the cursor, stretches during a Pomodoro break,
/// dozes off (z z Z) when a session has waited long (hovering wakes him), and
/// leaves either home — a wave, then off behind the camera — or with a happy
/// hop when you came to look. Drawn from the terminal logo's block characters:
/// each pixel is twice as tall as wide, like half a cell.
struct Clawd: View {
    /// Width of one pixel (whole points stay crisp on Retina); 18 × 10 of these.
    var pixel: CGFloat = 1
    /// Say hello when he appears and liven up (off in lists and drawings).
    var lively = true
    var asleep = false
    /// -1 left, 0 ahead, 1 right.
    var look = 0
    /// A Pomodoro break: stretch now and then.
    var stretching = false
    var exit: ClawdExit?

    private static let shape: [String] = [
        "...############...",
        "...##.######.##...",
        ".################.",
        "...############...",
        "....#.#....#.#....",
    ]

    @State private var blink = false
    @State private var wave = false
    @State private var armsUp = false
    @State private var hop: CGFloat = 0
    @State private var stomp: Int? = nil          // 0: left feet up, 1: right feet up
    @State private var arrived = false
    @State private var gone = false
    @State private var walkX: CGFloat = 0
    @State private var breathe = false
    @State private var dozed = false              // was asleep: wake with a start
    @State private var zPuff = 0                  // one "z" drifting up per step
    @State private var gaze: Int? = nil           // where he looks, overriding `look`

    private var width: CGFloat { pixel * 18 }
    private var eyesShut: Bool { blink || (asleep && lively && exit == nil) }

    var body: some View {
        Canvas { ctx, _ in
            // One path for all the pixels: filled at once, with no seams between them.
            let w = pixel, h = pixel * 2
            let eyes = Set([5, 12].map { $0 + (gaze ?? look) })
            var path = Path()
            func put(_ x: Int, _ y: Int) {
                path.addRect(CGRect(x: CGFloat(x) * w, y: CGFloat(y) * h, width: w, height: h))
            }
            for (y, row) in Self.shape.enumerated() {
                for (x, c) in row.enumerated() {
                    var on = c == "#"
                    if y == 1 { on = (3...14).contains(x) && !eyes.contains(x) }          // eyes where he looks
                    if (wave || armsUp) && x == 16 && y == 2 { on = false }                // right arm up…
                    if armsUp && x == 1 && y == 2 { on = false }                           // …and the left one
                    if y == 4, let side = stomp, side == 0 ? x < 9 : x >= 9 { on = false } // a foot up
                    if on { put(x, y) }
                }
            }
            if wave || armsUp { put(16, 1) }
            if armsUp { put(16, 0); put(1, 1); put(1, 0) }
            // Shut eyes: a thin line low in each, the rest filled in.
            if eyesShut {
                for x in eyes {
                    path.addRect(CGRect(x: CGFloat(x) * w, y: h, width: w, height: h * 0.62))
                    path.addRect(CGRect(x: CGFloat(x) * w, y: h * 1.87, width: w, height: h * 0.13))
                }
            }
            ctx.fill(path, with: .color(.coral))
        }
        .frame(width: width, height: pixel * 10)
        .overlay(alignment: .topTrailing) {
            if asleep && lively && exit == nil {
                SleepZ(big: zPuff % 3 == 2).id(zPuff).offset(x: 5, y: -3)
            }
        }
        .scaleEffect(x: 1, y: (armsUp ? 1.14 : 1) * (breathe ? 0.93 : 1), anchor: .bottom)
        .offset(x: walkX, y: -hop)
        .scaleEffect(arrived || !lively ? 1 : 0.4, anchor: .bottom)
        .opacity(!lively ? 1 : (arrived && !gone ? 1 : 0))
        .task(id: Mood(asleep: asleep, exit: exit, stretching: stretching)) { await live() }
    }

    private struct Mood: Hashable {
        var asleep: Bool, exit: ClawdExit?, stretching: Bool
    }

    // MARK: - Behaviour

    @MainActor private func live() async {
        guard lively else { return }
        if let exit { await leave(exit); return }
        if !arrived {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { arrived = true }
            await pause(450)
            await waveHello()
        }
        if asleep { await doze(); return }
        if breathe { withAnimation(.easeOut(duration: 0.3)) { breathe = false } }
        if dozed {                                                    // woken up: a start
            dozed = false
            await jump(3)
        }
        // A sign of life every 3–5 seconds, never the same twice running; on a
        // break, every other one is a stretch.
        var last = -1
        while !Task.isCancelled {
            await pause(Int.random(in: 3000...5000))
            if Task.isCancelled { return }
            if stretching && last != 9 { last = 9; await stretch(); continue }
            var next = Int.random(in: 0..<4)
            if next == last { next = (next + 1) % 4 }
            last = next
            switch next {
            case 0: await waveHello()
            case 1: await stompFeet(4)
            case 2: await doBlink()
            default: await jump(2); await jump(2)
            }
        }
    }

    /// Eyes shut, breathing slowly, a "z" drifting up every couple of seconds.
    @MainActor private func doze() async {
        dozed = true
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        while !Task.isCancelled {
            zPuff += 1
            await pause(1800)
        }
    }

    @MainActor private func leave(_ how: ClawdExit) async {
        arrived = true
        if breathe { withAnimation(.easeOut(duration: 0.2)) { breathe = false } }
        switch how {
        case .happy:
            await jump(5)
            withAnimation(.easeIn(duration: 0.25)) { gone = true }
        case .home:
            await waveHello()
            gaze = -1
            // Off to the left, stomping, behind the camera (the island clips him).
            // Just far enough to pass the island's left edge, at a walk.
            withAnimation(.linear(duration: 1.7)) { walkX = -(width + 14) }
            await stompFeet(7)
            gone = true
        }
    }

    @MainActor private func waveHello() async {
        for _ in 0..<2 {
            wave = true
            await pause(220)
            wave = false
            await pause(220)
        }
    }

    /// Left, right, left, right — stomping in place (or walking).
    @MainActor private func stompFeet(_ steps: Int) async {
        for i in 0..<steps {
            stomp = i % 2
            await pause(170)
            stomp = nil
            await pause(70)
        }
    }

    @MainActor private func doBlink() async {
        blink = true
        await pause(140)
        blink = false
        await pause(180)
        blink = true
        await pause(140)
        blink = false
    }

    @MainActor private func jump(_ height: CGFloat) async {
        withAnimation(.easeOut(duration: 0.14)) { hop = height }
        await pause(150)
        withAnimation(.easeIn(duration: 0.14)) { hop = 0 }
        await pause(170)
    }

    /// Arms up, taller for a moment, and down.
    @MainActor private func stretch() async {
        withAnimation(.easeOut(duration: 0.35)) { armsUp = true }
        await pause(900)
        withAnimation(.easeIn(duration: 0.3)) { armsUp = false }
        await pause(300)
    }

    private func pause(_ ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }
}

/// One "z" drifting up and fading, beside a sleeping Clawd.
private struct SleepZ: View {
    let big: Bool
    @State private var up = false

    var body: some View {
        Text(verbatim: big ? "Z" : "z")
            .font(.system(size: big ? 7 : 6, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .offset(x: up ? 4 : 0, y: up ? -9 : 0)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.15 : 0.7)
            .onAppear { withAnimation(.easeOut(duration: 1.7)) { up = true } }
    }
}
