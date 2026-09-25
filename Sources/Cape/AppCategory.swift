import SwiftUI

/// A broad bucket for Screen Time's day breakdown, picked automatically:
/// first a table of well-known apps (browsers, terminals, messengers — which
/// don't declare a category, or declare one that doesn't say much), then the
/// category the app declares itself (`LSApplicationCategoryType`), else Other.
enum AppCategory: String, CaseIterable, Identifiable {
    case work, browsing, social, entertainment, learning, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .work: return "Work"
        case .browsing: return "Browsing"
        case .social: return "Social"
        case .entertainment: return "Entertainment"
        case .learning: return "Learning"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .work: return .coral
        case .browsing: return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .social: return Color(red: 0.35, green: 0.82, blue: 0.62)
        case .entertainment: return Color(red: 0.78, green: 0.5, blue: 1.0)
        case .learning: return Color(red: 1.0, green: 0.8, blue: 0.3)
        case .other: return Color.white.opacity(0.35)
        }
    }

    /// Category of the app bundle at `path` (nil path → Other). Cached.
    static func of(path: String?) -> AppCategory {
        guard let path else { return .other }
        if let hit = cache[path] { return hit }
        let bundle = Bundle(path: path)
        let category = bundle?.bundleIdentifier.flatMap(known)
            ?? (bundle?.infoDictionary?["LSApplicationCategoryType"] as? String).flatMap(declared)
            ?? .other
        cache[path] = category
        return category
    }

    private static var cache: [String: AppCategory] = [:]

    // MARK: - Well-known apps (by bundle id)

    private static let knownIDs: [String: AppCategory] = [
        // Browsers
        "com.apple.Safari": .browsing, "com.google.Chrome": .browsing, "org.mozilla.firefox": .browsing,
        "company.thebrowser.Browser": .browsing, "company.thebrowser.dia": .browsing,
        "com.brave.Browser": .browsing, "com.microsoft.edgemac": .browsing,
        "com.operasoftware.Opera": .browsing, "com.vivaldi.Vivaldi": .browsing,
        "app.zen-browser.zen": .browsing, "ru.yandex.desktop.yandex-browser": .browsing,
        "org.chromium.Chromium": .browsing,
        // Work — terminals, editors, AI, office, design, calls
        "com.apple.Terminal": .work, "com.googlecode.iterm2": .work, "com.mitchellh.ghostty": .work,
        "net.kovidgoyal.kitty": .work, "org.alacritty": .work, "io.alacritty": .work,
        "dev.warp.Warp-Stable": .work, "com.github.wez.wezterm": .work,
        "com.microsoft.VSCode": .work, "com.todesktop.230313mzl4w4u92": .work, "dev.zed.Zed": .work,
        "com.sublimetext.4": .work, "com.apple.dt.Xcode": .work,
        "com.anthropic.claudefordesktop": .work, "com.openai.chat": .work,
        "com.figma.Desktop": .work, "notion.id": .work, "md.obsidian": .work,
        "com.tinyspeck.slackmacgap": .work, "us.zoom.xos": .work, "com.microsoft.teams2": .work,
        "com.apple.mail": .work, "com.apple.iCal": .work, "com.apple.Notes": .work,
        "com.apple.reminders": .work, "com.apple.Preview": .work, "com.apple.TextEdit": .work,
        "com.apple.iWork.Pages": .work, "com.apple.iWork.Numbers": .work, "com.apple.iWork.Keynote": .work,
        "com.microsoft.Word": .work, "com.microsoft.Excel": .work, "com.microsoft.Powerpoint": .work,
        "com.microsoft.Outlook": .work, "com.docker.docker": .work, "com.postmanlabs.mac": .work,
        "ru.mail.messenger-biz-avocado-desktop": .work,   // VK WorkSpace — a work messenger
        "com.microsoft.rdc.macos": .work,                 // Windows App (remote desktop)
        // Other — system apps that declare "productivity"
        "com.apple.finder": .other,
        // Social
        "ru.keepcoder.Telegram": .social, "com.tdesktop.Telegram": .social,
        "net.whatsapp.WhatsApp": .social, "com.hnc.Discord": .social,
        "com.apple.MobileSMS": .social, "com.apple.FaceTime": .social, "com.facebook.archon": .social,
        "com.vk.messenger": .social,
        // Entertainment
        "com.spotify.client": .entertainment, "com.apple.Music": .entertainment,
        "com.apple.TV": .entertainment, "com.apple.podcasts": .entertainment,
        "org.videolan.vlc": .entertainment, "com.colliderli.iina": .entertainment,
        "com.valvesoftware.steam": .entertainment, "com.apple.Photos": .entertainment,
        // Learning
        "com.apple.iBooksX": .learning, "com.apple.Dictionary": .learning,
    ]
    private static let knownPrefixes: [(String, AppCategory)] = [
        ("com.jetbrains.", .work), ("com.microsoft.VSCode", .work), ("com.google.Chrome", .browsing),
    ]

    private static func known(_ id: String) -> AppCategory? {
        knownIDs[id] ?? knownPrefixes.first { id.hasPrefix($0.0) }?.1
    }

    // MARK: - Declared category (App Store categories)

    private static func declared(_ type: String) -> AppCategory? {
        let t = type.replacingOccurrences(of: "public.app-category.", with: "")
        if t.hasSuffix("-games") || t == "games" { return .entertainment }
        switch t {
        case "developer-tools", "productivity", "business", "finance", "graphics-design":
            return .work
        case "social-networking":
            return .social
        case "entertainment", "music", "video", "photography", "sports", "lifestyle":
            return .entertainment
        case "education", "reference", "news", "books":
            return .learning
        default:
            return nil   // utilities, weather, … — Other
        }
    }
}
