import AppKit

/// The app's icon, picked in Settings › General: Monet — the bundle's own
/// AppIcon.icns, the default — or one of the others (Resources/Icons/<name>.png).
///
/// Another one is set as the bundle's custom icon (NSWorkspace.setIcon), so
/// Finder, Launchpad and Spotlight show it too; picking Monet clears it. The
/// signature still verifies and the app's identity is the same, so macOS keeps
/// its permissions. An update replaces the bundle, and with it the custom icon
/// — so it's applied again at every launch.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case monet, classic, sunrise, lilies

    static let key = "appIcon"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return String(localized: "Classic")
        case .monet: return String(localized: "Monet")
        case .sunrise: return String(localized: "Sunrise")
        case .lilies: return String(localized: "Water Lilies")
        }
    }

    /// The picture (Monet is the bundle's own AppIcon.icns).
    var image: NSImage? {
        switch self {
        case .monet:
            return Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        default:
            return Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Icons")
                .flatMap(NSImage.init(contentsOf:))
        }
    }

    static var saved: AppIconChoice {
        AppIconChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .monet
    }

    /// Show this icon: in Cape itself (the tour, alerts) and, for a real .app,
    /// on the bundle. False if the bundle couldn't be changed (a read-only place).
    @discardableResult
    func apply() -> Bool {
        let picture = image
        NSApp.applicationIconImage = picture
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return true }
        let ok = NSWorkspace.shared.setIcon(self == .monet ? nil : picture, forFile: bundle.path, options: [])
        // A fresh modification date nudges Finder and Launchpad to redraw it.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundle.path)
        return ok
    }

    /// At launch: put a picked icon back (an update brings Monet again).
    static func applyAtLaunch() {
        let choice = saved
        if choice == .monet {
            if let icon = choice.image { NSApp.applicationIconImage = icon }
        } else {
            choice.apply()
        }
    }
}
