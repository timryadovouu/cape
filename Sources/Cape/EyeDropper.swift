import AppKit

/// Screen color picker: shows the system magnifier loupe (NSColorSampler — no
/// permission needed), and puts the picked color's `#RRGGBB` on the pasteboard,
/// where the buffer captures it like any other copy.
enum EyeDropper {
    /// Kept alive while the loupe is up.
    private static var sampler: NSColorSampler?

    /// `onPick` gets the hex string and the color (sRGB); not called on Esc.
    static func pick(_ onPick: @escaping (String, NSColor) -> Void) {
        let s = NSColorSampler()
        sampler = s
        s.show { color in
            sampler = nil
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = hexString(c)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string)
            onPick(hex, c)
        }
    }

    static func hexString(_ c: NSColor) -> String {
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
