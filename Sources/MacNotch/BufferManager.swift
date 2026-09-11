import AppKit

enum BufferKind {
    case text, image, file
}

/// One saved clipboard entry, backed by a real file on disk.
struct BufferItem: Identifiable, Hashable {
    let id: String        // absolute file path
    let url: URL
    let kind: BufferKind
    let date: Date
    var isFavorite: Bool = false
    var name: String { url.lastPathComponent }
}

/// Persistent clipboard buffer.
///
/// Everything copied is saved as a real file under `~/Documents/localBuffer`,
/// into a per-day subfolder named like `2026-09-04`. Supports text, images and
/// any copied files (photos, videos, documents, ...). Day folders older than
/// `retentionDays` are deleted automatically.
final class BufferManager: ObservableObject {
    @Published private(set) var recent: [BufferItem] = []

    private(set) var rootURL: URL
    let maxRecent = 20

    /// Fired on a new external copy — used for the "brow widens left" effect.
    var onNewItem: ((BufferItem) -> Void)?

    private let settings: Settings
    private var lastChangeCount: Int
    private var lastText: String?
    private var lastDay: String = ""
    private var reloadTick = 0
    private var timer: Timer?
    private let io = DispatchQueue(label: "io.macnotch.localBuffer")

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH-mm-ss-SSS"; return f
    }()
    private static let imageExts: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp", "webp"]

    /// Favorited items live in this folder instead of a `yyyy-MM-dd` day folder,
    /// which keeps them clear of day-rollover/retention cleanup and pins them on
    /// top. The folder's non-date name means the cleanup passes skip it for free.
    static let favoritesDirName = "_favorites"

    init(settings: Settings) {
        self.settings = settings
        rootURL = settings.bufferRoot
        lastChangeCount = NSPasteboard.general.changeCount
        lastDay = Self.dayFormatter.string(from: Date())

        migrateFromDocuments()   // one-time move out of the TCC-protected Documents folder
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        cleanupOld()
        reloadItems()

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Move the buffer out of ~/Documents/localBuffer (TCC-protected, prompts on
    /// every launch) into Application Support. Runs once, only for users still on
    /// the old Documents default.
    private func migrateFromDocuments() {
        let fm = FileManager.default
        let oldURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("localBuffer")
        guard settings.bufferRootPath == oldURL.path else { return }

        let newURL = AppModules.supportDirectory.appendingPathComponent("localBuffer")
        if fm.fileExists(atPath: oldURL.path) {
            if !fm.fileExists(atPath: newURL.path) {
                try? fm.moveItem(at: oldURL, to: newURL)
            } else {
                // Merge day-folders into the existing destination.
                let days = (try? fm.contentsOfDirectory(at: oldURL, includingPropertiesForKeys: nil)) ?? []
                for day in days {
                    let dest = newURL.appendingPathComponent(day.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: day, to: dest) }
                }
                try? fm.removeItem(at: oldURL)
            }
        }
        // Only switch to the new location once the data has actually left Documents
        // (so a denied-permission move retries on a later launch instead of
        // abandoning the old buffer).
        if !fm.fileExists(atPath: oldURL.path) {
            settings.bufferRootPath = newURL.path
            rootURL = newURL
        }
    }

    /// Re-read the folder / retention from settings (call after they change).
    func applySettings() {
        rootURL = settings.bufferRoot
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        cleanupOld()
        reloadItems()
    }

    /// Delete the whole buffer for today.
    func clearToday() {
        let today = rootURL.appendingPathComponent(Self.dayFormatter.string(from: Date()))
        try? FileManager.default.removeItem(at: today)
        reloadItems()
    }

    /// Delete a single entry.
    func delete(_ item: BufferItem) {
        try? FileManager.default.removeItem(at: item.url)
        reloadItems()
    }

    /// Star / unstar an item. Favoriting moves its file into the `_favorites`
    /// folder — so cleanup leaves it alone and it pins to the top; unfavoriting
    /// moves it back into today's folder.
    func toggleFavorite(_ item: BufferItem) {
        let dest = item.isFavorite
            ? uniqueURL(in: todayURL(), name: item.name)
            : uniqueURL(in: favoritesURL(), name: item.name)
        try? FileManager.default.moveItem(at: item.url, to: dest)
        reloadItems()
    }

    private func favoritesURL() -> URL {
        let url = rootURL.appendingPathComponent(Self.favoritesDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Pasteboard monitoring

    /// When the calendar day changes, optionally delete the day that just ended.
    private func checkDayRollover() {
        let today = Self.dayFormatter.string(from: Date())
        guard today != lastDay else { return }
        let ended = lastDay
        lastDay = today
        if settings.clearBufferAtEndOfDay {
            try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(ended))
        }
        cleanupOld()
        reloadItems()
    }

    private func check() {
        checkDayRollover()

        // Every ~2s, rescan so files deleted/added directly in the folder
        // (e.g. in Finder) are reflected in the notch. reloadItems() is a no-op
        // when nothing changed.
        reloadTick += 1
        if reloadTick % 4 == 0 { reloadItems() }

        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Read the pasteboard on the main thread, then do the heavy file I/O
        // off the main thread so large videos don't hitch the UI.
        let fileURLs = pb.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let image = NSImage(pasteboard: pb)
        let text = pb.string(forType: .string)

        io.async { [weak self] in
            guard let self else { return }
            var saved: BufferItem?

            if let urls = fileURLs, !urls.isEmpty {
                for u in urls { saved = self.saveFile(from: u) ?? saved }
            } else if let image {
                saved = self.saveImage(image)
            } else if let text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if text == self.lastText { return }
                self.lastText = text
                saved = self.saveText(text)
            }

            guard let item = saved else { return }
            DispatchQueue.main.async {
                self.reloadItems()
                self.onNewItem?(item)
            }
        }
    }

    // MARK: - Saving

    private func todayURL() -> URL {
        let url = rootURL.appendingPathComponent(Self.dayFormatter.string(from: Date()),
                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func saveFile(from src: URL) -> BufferItem? {
        let dest = uniqueURL(in: todayURL(), name: src.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return item(for: dest)
        } catch {
            return nil
        }
    }

    private func saveImage(_ image: NSImage) -> BufferItem? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dest = todayURL().appendingPathComponent(stampName(ext: "png"))
        try? png.write(to: dest)
        return item(for: dest)
    }

    private func saveText(_ text: String) -> BufferItem? {
        let dest = todayURL().appendingPathComponent(stampName(ext: "txt"))
        try? text.data(using: .utf8)?.write(to: dest)
        return item(for: dest)
    }

    private func stampName(ext: String) -> String {
        "\(Self.stampFormatter.string(from: Date())).\(ext)"
    }

    private func uniqueURL(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(next)
            i += 1
        }
        return candidate
    }

    // MARK: - Listing / retention

    private func item(for url: URL) -> BufferItem {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? Date()
        let favorite = url.deletingLastPathComponent().lastPathComponent == Self.favoritesDirName
        return BufferItem(id: url.path, url: url, kind: kind(for: url), date: date, isFavorite: favorite)
    }

    private func kind(for url: URL) -> BufferKind {
        let ext = url.pathExtension.lowercased()
        if ext == "txt" { return .text }
        if Self.imageExts.contains(ext) { return .image }
        return .file
    }

    /// Rescan the retained day folders for recent items (newest first).
    func reloadItems() {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(at: rootURL,
                                                     includingPropertiesForKeys: nil) else {
            recent = []; return
        }
        var all: [BufferItem] = []
        for day in days where (try? day.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let files = (try? fm.contentsOfDirectory(at: day,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            all.append(contentsOf: files.map { item(for: $0) })
        }
        // Favorites pinned on top, then newest-first.
        all.sort { a, b in
            a.isFavorite == b.isFavorite ? a.date > b.date : a.isFavorite
        }
        let newItems = Array(all.prefix(maxRecent))
        // Only republish when the on-disk set actually changed (so external
        // deletions/additions show up, but we don't churn the UI otherwise).
        if newItems.map(\.id) != recent.map(\.id) {
            recent = newItems
        }
    }

    private func cleanupOld() {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(at: rootURL,
                                                     includingPropertiesForKeys: nil) else { return }

        // When "clear at end of day" is on, keep only today's folder.
        if settings.clearBufferAtEndOfDay {
            let today = Self.dayFormatter.string(from: Date())
            for day in days {
                guard Self.dayFormatter.date(from: day.lastPathComponent) != nil else { continue }
                if day.lastPathComponent != today { try? fm.removeItem(at: day) }
            }
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.bufferRetentionDays,
                                           to: Calendar.current.startOfDay(for: Date()))!
        for day in days {
            guard let date = Self.dayFormatter.date(from: day.lastPathComponent) else { continue }
            if date < cutoff { try? fm.removeItem(at: day) }
        }
    }

    // MARK: - Actions

    /// Copy an item back to the system pasteboard.
    func copyToPasteboard(_ item: BufferItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            let s = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
            pb.setString(s, forType: .string)
        case .image:
            if let img = NSImage(contentsOf: item.url) { pb.writeObjects([img]) }
            else { pb.writeObjects([item.url as NSURL]) }
        case .file:
            pb.writeObjects([item.url as NSURL])
        }
        lastChangeCount = pb.changeCount   // don't re-capture our own copy
    }

    /// Open the localBuffer folder in Finder to browse all dates.
    func openInFinder() {
        NSWorkspace.shared.open(rootURL)
    }
}
