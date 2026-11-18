import AppKit
import Carbon
import SwiftUI

/// One-shot utilities — not tabs. They live on the Tools page (the grid button
/// in the rail) and can each get a global shortcut in Settings › Tools.
enum Tool: String, CaseIterable, Identifiable {
    case colorPicker, cleanKeyboard, myIP
    var id: String { rawValue }

    var name: String {
        switch self {
        case .colorPicker: return String(localized: "Pick color")
        case .cleanKeyboard: return String(localized: "Clean keyboard")
        case .myIP: return String(localized: "Get my IP")
        }
    }
    var detail: String {
        switch self {
        case .colorPicker: return String(localized: "Copies the hex to the buffer")
        case .cleanKeyboard: return String(localized: "Locks keys while you wipe it")
        case .myIP: return String(localized: "Country and public IPv4")
        }
    }
    var icon: String {
        switch self {
        case .colorPicker: return "eyedropper"
        case .cleanKeyboard: return "keyboard"
        case .myIP: return "globe.europe.africa"
        }
    }
    /// Stable id for the global hotkey registration.
    var hotkeyID: UInt32 {
        switch self {
        case .colorPicker: return 1
        case .cleanKeyboard: return 2
        case .myIP: return 3
        }
    }
}

/// Everything on the Tools page — the one-shot tools, Ports and the two
/// switches — in the order and with the visibility set in Settings › Tools.
enum ToolItem: String, CaseIterable, Identifiable {
    case colorPicker, cleanKeyboard, ports, myIP, reverseWheel, qrInImages
    var id: String { rawValue }

    /// The one-shot tool behind it, if it is one.
    var tool: Tool? { Tool(rawValue: rawValue) }

    var name: String {
        switch self {
        case .ports: return String(localized: "Ports")
        case .reverseWheel: return String(localized: "Reverse wheel")
        case .qrInImages: return String(localized: "QR in images")
        default: return tool?.name ?? rawValue
        }
    }
    var icon: String {
        switch self {
        case .ports: return "point.3.connected.trianglepath.dotted"
        case .reverseWheel: return "computermouse"
        case .qrInImages: return "qrcode.viewfinder"
        default: return tool?.icon ?? "questionmark"
        }
    }
}

extension AppModules {
    /// Run a tool — from its tile or its global shortcut.
    func run(_ tool: Tool, state: NotchState) {
        guard settings.isToolOn(tool) else { return }    // switched off in Settings › Tools
        switch tool {
        case .colorPicker:
            EyeDropper.pick { hex, color in state.flashColor(hex, Color(nsColor: color)) }
        case .cleanKeyboard:
            keyboardCleaner.start()
        case .myIP:
            state.lookUpIP?()
        }
    }
}

// MARK: - Get my IP

/// The public IP and its country, from 2ip.io — asked only when Get my IP is
/// used (or tested in Settings › Tools). The country's name comes from macOS,
/// in the app's language.
enum IPLookup {
    static let endpoint = "https://api.2ip.io/"

    struct Result: Equatable {
        var ip: String
        var code: String?         // "NL"; nil when the service doesn't know

        /// 🇳🇱 — from the two letters' regional indicator symbols.
        var flag: String? {
            guard let code, code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }),
                  code != "XX" else { return nil }
            return String(String.UnicodeScalarView(code.uppercased().unicodeScalars
                .compactMap { UnicodeScalar(127_397 + $0.value) }))
        }
        var country: String? {
            guard flag != nil, let code else { return nil }
            return AppLanguage.locale.localizedString(forRegionCode: code)
        }
    }

    /// {"ip": "89.105.203.226", "code": "NL", …}
    static func fetch() async -> Result? {
        guard let data = try? await get(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else { return nil }
        return Result(ip: ip, code: json["code"] as? String)
    }

    /// Settings › Tools › Test: where the request actually went (the final URL,
    /// after any redirect), the status and the time — then the answer as it
    /// came, pretty-printed, or the error.
    static func rawAnswer() async -> String {
        let start = Date()
        do {
            let (data, response) = try await send()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let http = response as? HTTPURLResponse
            let head = "GET \(http?.url?.absoluteString ?? endpoint) → HTTP \(http?.statusCode ?? 0) · \(ms) ms"
            var body = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                body = text
            }
            return head + "\n\n" + body
        } catch {
            return "GET \(endpoint) → " + error.localizedDescription
        }
    }

    private static func get() async throws -> Data {
        let (data, response) = try await send()
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return data
    }

    /// The one request: GET over HTTPS, no cookies, no cache, "Cape" as the agent.
    private static func send() async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: endpoint)!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 5)
        req.httpShouldHandleCookies = false
        req.setValue("Cape", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: req)
    }
}

// MARK: - Shortcut

/// A recorded key combination (at least one of ⌘ ⌥ ⌃, optionally ⇧).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt          // NSEvent.ModifierFlags raw value
    var key: String              // display name of the key, e.g. "C", "Space", "F5"

    var display: String {
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Key name as printed on the keycap (ASCII layout, so a Russian layout still
    /// shows "C", not "С").
    static func keyName(_ keyCode: UInt16) -> String {
        let special: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let s = special[keyCode] { return s }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Global hotkeys

/// System-wide shortcuts via Carbon `RegisterEventHotKey` — no Accessibility
/// permission needed (unlike watching bare modifiers such as double-⌥).
final class GlobalHotkeys: ObservableObject {
    static let shared = GlobalHotkeys()

    /// Ids whose combination is already taken (by another app or another tool).
    @Published private(set) var failed: Set<UInt32> = []

    private var entries: [UInt32: (shortcut: Shortcut, action: () -> Void)] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var paused = false
    private static let signature: OSType = 0x4341_5045   // 'CAPE'

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotkey = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            if err == noErr {
                let id = hotkey.id
                DispatchQueue.main.async { GlobalHotkeys.shared.entries[id]?.action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(id: UInt32, _ shortcut: Shortcut, action: @escaping () -> Void) {
        unregister(id: id)
        entries[id] = (shortcut, action)
        if !paused { install(id) }
    }

    func unregister(id: UInt32) {
        uninstall(id)
        entries[id] = nil
        failed.remove(id)
    }

    /// While a shortcut is being recorded, stand down so the combo reaches the
    /// recorder instead of firing a tool.
    func setPaused(_ on: Bool) {
        guard on != paused else { return }
        paused = on
        if on { refs.keys.forEach(uninstall) } else { entries.keys.sorted().forEach(install) }
    }

    private func install(_ id: UInt32) {
        guard let entry = entries[id] else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(entry.shortcut.keyCode), entry.shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            failed.remove(id)
        } else {
            failed.insert(id)
        }
    }

    private func uninstall(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}

// MARK: - Settings: shortcut recorder

/// "Record Shortcut" button: click, press a combination (with ⌘, ⌥ or ⌃).
/// Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let hotkeyID: UInt32
    @ObservedObject private var hotkeys = GlobalHotkeys.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Button { recording ? stop() : start() } label: {
                    Text(recording ? String(localized: "Type shortcut…") : shortcut?.display ?? String(localized: "Record Shortcut"))
                        .monospacedDigit()
                        .frame(minWidth: 110)
                }
                if shortcut != nil, !recording {
                    Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove the shortcut")
                }
            }
            if hotkeys.failed.contains(hotkeyID), !recording {
                Text("Already used by another app or tool")
                    .font(.caption2).foregroundStyle(.red)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        GlobalHotkeys.shared.setPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stop(); return nil }                     // Esc — cancel
            if mods.isEmpty, event.keyCode == 51 || event.keyCode == 117 {    // ⌫ — clear
                shortcut = nil; stop(); return nil
            }
            guard !mods.isDisjoint(with: [.command, .option, .control]) else {
                NSSound.beep(); return nil                                    // needs ⌘/⌥/⌃
            }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue,
                                key: Shortcut.keyName(event.keyCode))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalHotkeys.shared.setPaused(false)
    }
}

// MARK: - Tools page (in the notch)

struct ToolsPanel: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: NotchState
    let modules: AppModules

    // Rearranging — hold a tile, like widgets on an iPhone: they wiggle, drag
    // one to its new place, click anywhere (or Done) to finish.
    @State private var editing = false
    @State private var order: [ToolItem] = []
    @State private var dragging: ToolItem?
    @State private var dragPoint: CGPoint = .zero     // the cursor, in the grid
    @State private var grabOffset: CGSize = .zero     // …from the tile's top-left

    /// Two to a row, three rows at most; a tile alone in its row spans it.
    private static let columns = 2, maxRows = 3
    static let tileHeight: CGFloat = 44
    private static let hGap: CGFloat = 8, vGap: CGFloat = 6

    var body: some View {
        if state.showingPorts && settings.showPorts {
            PortsPage(ports: modules.ports) { state.showingPorts = false }
        } else {
            page
        }
    }

    private var items: [ToolItem] {
        Array((editing ? order : settings.shownToolItems).prefix(Self.columns * Self.maxRows))
    }

    private var page: some View {
        VStack(spacing: 6) {
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("All tools are hidden").font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                grid
            }
            Spacer(minLength: 0)
            footer
        }
    }

    // MARK: Grid

    private var gridHeight: CGFloat {
        let rows = (items.count + Self.columns - 1) / Self.columns
        return CGFloat(rows) * Self.tileHeight + CGFloat(max(0, rows - 1)) * Self.vGap
    }

    /// Where tile `i` of `count` goes in a grid `width` wide.
    private static func slot(_ i: Int, of count: Int, width: CGFloat) -> CGRect {
        let row = i / columns, col = i % columns
        let alone = count % columns == 1 && i == count - 1
        let w = alone ? width : (width - hGap) / 2
        return CGRect(x: alone ? 0 : CGFloat(col) * (w + hGap), y: CGFloat(row) * (tileHeight + vGap),
                      width: w, height: tileHeight)
    }

    /// Which slot a point falls in.
    private static func index(at p: CGPoint, of count: Int, width: CGFloat) -> Int {
        let row = max(0, Int(p.y / (tileHeight + vGap)))
        let alone = count % columns == 1 && row == (count - 1) / columns
        let col = alone ? 0 : (p.x > width / 2 ? 1 : 0)
        return min(count - 1, row * columns + col)
    }

    private var grid: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let list = items
            ZStack(alignment: .topLeading) {
                ForEach(Array(list.enumerated()), id: \.element) { i, item in
                    let slot = Self.slot(i, of: list.count, width: width)
                    let lifted = dragging == item
                    itemTile(item)
                        .frame(width: slot.width, height: Self.tileHeight)
                        .modifier(Wiggle(active: editing && !lifted, delay: Double(i) * 0.05))
                        .scaleEffect(lifted ? 1.04 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 10, y: 4)
                        .offset(x: lifted ? dragPoint.x - grabOffset.width : slot.minX,
                                y: lifted ? dragPoint.y - grabOffset.height : slot.minY)
                        .zIndex(lifted ? 1 : 0)
                        .allowsHitTesting(!editing)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            startEditing()
                        })
                }
            }
            .frame(width: width, height: gridHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width, count: list.count), including: editing ? .all : .subviews)
        }
        .frame(height: gridHeight)
    }

    private func dragGesture(width: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    // A click (no movement) on the grid ends the rearranging.
                    guard hypot(value.translation.width, value.translation.height) > 3 else { return }
                    let i = Self.index(at: value.startLocation, of: count, width: width)
                    guard order.indices.contains(i) else { return }
                    let slot = Self.slot(i, of: count, width: width)
                    grabOffset = CGSize(width: value.startLocation.x - slot.minX,
                                        height: value.startLocation.y - slot.minY)
                    dragging = order[i]
                }
                dragPoint = value.location
                guard let d = dragging, let from = order.firstIndex(of: d) else { return }
                let to = Self.index(at: value.location, of: count, width: width)
                if to != from {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    }
                }
            }
            .onEnded { _ in
                guard dragging != nil else { finishEditing(); return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragging = nil }
                settings.reorderShownTools(order + settings.shownToolItems.filter { !order.contains($0) })
            }
    }

    private func startEditing() {
        guard !editing else { return }
        order = settings.shownToolItems
        withAnimation(.easeOut(duration: 0.15)) { editing = true }
    }

    private func finishEditing() {
        dragging = nil
        withAnimation(.easeOut(duration: 0.15)) { editing = false }
    }

    private var footer: some View {
        Group {
            if editing {
                Button(action: finishEditing) {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Capsule().fill(Color.coral.opacity(0.14)))
                }
                .buttonStyle(.plain)
            } else {
                Button { modules.settingsWindow.show(.tools) } label: {
                    Text("Hold a tile to move it · shortcuts in Settings › Tools")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 20)
    }

    // MARK: Tiles

    /// While rearranging, a tile's own click does nothing.
    private func act(_ action: @escaping () -> Void) -> () -> Void {
        { if !editing { action() } }
    }
    private func guarded(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue }, set: { if !editing { binding.wrappedValue = $0 } })
    }

    @ViewBuilder private func itemTile(_ item: ToolItem) -> some View {
        switch item {
        case .ports:
            PortsTile(ports: modules.ports, action: act { state.showingPorts = true })
        case .myIP:
            ipTile
        case .reverseWheel:
            ToggleTile(name: item.name, detail: String(localized: "Mouse only, trackpad stays"),
                       icon: item.icon, isOn: guarded($settings.reverseMouseScroll))
        case .qrInImages:
            ToggleTile(name: item.name, detail: String(localized: "Adds links from screenshots"),
                       icon: item.icon, isOn: guarded($settings.scanQRInImages))
        case .colorPicker, .cleanKeyboard:
            if let tool = item.tool { tile(tool) }
        }
    }

    private func tile(_ tool: Tool) -> some View {
        ToolTile(tool: tool, shortcut: settings.toolShortcuts[tool.rawValue],
                 action: act { modules.run(tool, state: state) })
    }

    /// Get my IP shows its answer right in the tile; a second click copies the IP.
    private var ipTile: some View {
        let detail: String?
        switch state.myIP {
        case .loading?: detail = String(localized: "Checking your IP…")
        case .failed?: detail = String(localized: "No connection")
        case .found(let r)?:
            detail = [r.flag, r.country, r.ip].compactMap { $0 }.joined(separator: " ")
        case nil: detail = nil
        }
        return ToolTile(tool: .myIP, shortcut: settings.toolShortcuts[Tool.myIP.rawValue], detail: detail,
                        action: act {
            if case .found? = state.myIP { state.copyMyIP() } else { modules.run(.myIP, state: state) }
        })
    }
}

/// The rearranging wiggle: a slight rock back and forth, each tile a beat apart.
private struct Wiggle: ViewModifier {
    let active: Bool
    let delay: Double
    @State private var tilt = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (tilt ? 0.35 : -0.35) : 0))
            .onAppear { if active { start() } }
            .onChange(of: active) { on in on ? start() : stop() }
    }

    private func start() {
        tilt = false
        withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true).delay(delay)) { tilt = true }
    }
    private func stop() {
        withAnimation(.easeOut(duration: 0.12)) { tilt = false }
    }
}

/// A tool that stays on (a switch, not a one-shot) — same size as a ToolTile.
private struct ToggleTile: View {
    let name: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOn ? Color.coral : .white.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .background((isOn ? Color.coral : .white).opacity(isOn ? 0.14 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CoralSwitch(isOn: isOn)
            }
            .padding(7)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(hovering ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ToolTile: View {
    let tool: Tool
    let shortcut: Shortcut?
    /// In place of the tool's description (Get my IP: its answer).
    var detail: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.coral)
                    .frame(width: 30, height: 30)
                    .background(Color.coral.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.system(size: 12, weight: .semibold))
                    Text(verbatim: detail ?? tool.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(detail == nil ? 0.45 : 0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut.display)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(7)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(hovering ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
