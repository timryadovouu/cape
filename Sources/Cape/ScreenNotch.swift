import AppKit

/// Geometry of the physical notch on the active screen.
/// On Macs without a notch a synthetic top-center notch is used, so the app
/// still works on external monitors and older Macs.
struct NotchMetrics {
    let screenFrame: NSRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasRealNotch: Bool

    /// The physical notch only exists on the built-in laptop display, so anchor
    /// there: prefer a screen with a real notch, else the built-in display.
    /// Returns nil on a desktop Mac (no built-in display).
    static func builtInScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.screens.first { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) != 0
        }
    }

    static func current() -> NotchMetrics {
        // Built-in screen when there is one (laptops); otherwise the main screen
        // with a synthetic notch (desktops / external-only setups).
        let screen = builtInScreen()
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0

        let height: CGFloat = hasNotch ? topInset : 32

        var width: CGFloat = 200
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width,
           left > 0, right > 0 {
            width = frame.width - left - right
        }

        return NotchMetrics(
            screenFrame: frame,
            notchWidth: width,
            notchHeight: max(height, 30),
            hasRealNotch: hasNotch
        )
    }
}
