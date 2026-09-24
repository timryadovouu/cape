import AVFoundation
import AppKit

/// Thread-safe accumulator for mic samples — written from the audio-render thread,
/// read on stop. Sendable so the tap closure can use it without touching `self`.
private final class AudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func clear() { lock.lock(); samples.removeAll(); lock.unlock() }

    func append(from buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
    }

    func take() -> [Float] {
        lock.lock(); defer { samples.removeAll(); lock.unlock() }
        return samples
    }
}

/// Push-to-talk dictation: record the mic, transcribe locally (Whisper), and drop
/// the text on the system pasteboard — where the buffer module then captures it.
///
/// Transcription runs through WhisperKit when it's linked (see `Transcriber`); the
/// recording/plumbing here is engine-agnostic so it builds without the dependency.
/// `@unchecked Sendable`: all published state is mutated only on the main queue and
/// the audio samples are lock-guarded.
final class VoiceDictation: ObservableObject, @unchecked Sendable {
    enum Status: Equatable { case idle, recording, transcribing, downloading, loading }
    @Published private(set) var status: Status = .idle
    @Published private(set) var downloadProgress: Double = 0   // 0…1 while a model downloads

    /// Whether the selected model is on disk — drives the mic button (disabled +
    /// hint when missing) and the Settings download/delete controls.
    var modelDownloaded: Bool { Transcriber.isModelDownloaded(settings.voiceModel) }

    private let settings: Settings
    private let todo: TodoStore
    private var engine = AVAudioEngine()
    private let audio = AudioBuffer()
    private let hotkey = DictationHotkey()
    private var recordRate: Double = 16_000
    private static let targetRate: Double = 16_000   // Whisper wants 16 kHz mono

    init(settings: Settings, todo: TodoStore) {
        self.settings = settings
        self.todo = todo
        hotkey.onTrigger = { [weak self] in self?.toggle() }
        hotkey.onHoldStart = { [weak self] in self?.holdStart() }
        hotkey.onHoldEnd = { [weak self] in self?.holdEnd() }
        hotkey.onHoldCancel = { [weak self] in self?.holdCancel() }
        applyHotkey(prompt: false)   // restore, no prompt on launch
    }

    /// Apply the global dictation keys from Settings (double-tap and/or hold-to-
    /// talk). Prompts for Accessibility access when one is being switched on.
    func applyHotkey(prompt: Bool = true) {
        hotkey.trigger = VoiceHotkeyTrigger(rawValue: settings.voiceHotkeyTrigger) ?? .option
        hotkey.doubleTapEnabled = settings.voiceHotkey
        hotkey.holdFn = settings.voiceHoldFn
        hotkey.holdRightOption = settings.voiceHoldRightOption
        guard settings.voiceHotkey || settings.voiceHoldFn || settings.voiceHoldRightOption else {
            hotkey.stop(); return
        }
        if prompt { DictationHotkey.requestAccessibilityPrompt() }
        hotkey.start()
    }

    // MARK: - Push-to-talk

    /// True while the current recording was started by holding a key — only then
    /// does releasing that key stop it (a double-tap recording is left alone).
    private var startedByHold = false
    private var holdActive = false

    private func holdStart() {
        holdActive = true
        guard status == .idle else { return }
        startedByHold = true
        requestAndStart(fromHold: true)
    }

    private func holdEnd() {
        holdActive = false
        guard startedByHold else { return }
        startedByHold = false
        if status == .recording { stop() }
    }

    /// The held key turned out to be part of a chord (⌥+letter, Fn+⌫…) — drop
    /// the recording without transcribing it.
    private func holdCancel() {
        holdActive = false
        guard startedByHold else { return }
        startedByHold = false
        if status == .recording { discardRecording() }
    }

    private func discardRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _ = audio.take()
        status = .idle
    }

    /// Apply a changed shortcut modifier live (the monitors read `trigger` per event).
    func updateHotkeyTrigger() {
        hotkey.trigger = VoiceHotkeyTrigger(rawValue: settings.voiceHotkeyTrigger) ?? .option
    }

    // MARK: - Control

    func toggle() {
        switch status {
        case .idle: requestAndStart()
        case .recording: stop()
        case .transcribing, .downloading, .loading: break   // busy — ignore
        }
    }

    /// Delete the selected model from disk (and unload it from memory). Re-download
    /// it any time from Settings › Voice.
    func deleteModel() {
        let model = settings.voiceModel
        try? FileManager.default.removeItem(at: Transcriber.modelFolder(model))
        Task { await Transcriber.unload(model) }
        objectWillChange.send()   // refresh the downloaded/✓ state in the UI
    }

    /// Pre-download and load the selected model so the first dictation is instant.
    /// Progress is shown in Settings › Voice (not in the notch).
    func prepareModel() {
        guard status == .idle else { return }
        let model = settings.voiceModel
        downloadProgress = 0
        status = .downloading
        Task { [weak self] in
            _ = await Transcriber.prepare(model: model) { fraction in
                DispatchQueue.main.async {
                    self?.downloadProgress = fraction
                    self?.status = fraction < 1.0 ? .downloading : .loading
                }
            }
            DispatchQueue.main.async { self?.status = .idle }
        }
    }

    /// Warm the model in the background at launch so the first dictation isn't slow
    /// (loading the CoreML model takes a few seconds, especially right after a
    /// reboot). Only loads a model that's already on disk — never downloads here.
    /// Shows `.loading` so the mic button is disabled until the model is ready.
    func preloadIfReady() {
        guard settings.voicePreload, status == .idle,
              Transcriber.isModelDownloaded(settings.voiceModel) else { return }
        let model = settings.voiceModel
        status = .loading
        Task { [weak self] in
            _ = await Transcriber.prepare(model: model) { _ in }
            DispatchQueue.main.async { if self?.status == .loading { self?.status = .idle } }
        }
    }

    /// Ask for microphone access asynchronously (never blocks the UI), then record.
    /// Requesting permission implicitly via `engine.start()` could hang the app.
    private func requestAndStart(fromHold: Bool = false) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // A push-to-talk key released during the permission prompt
                    // must not leave a recording running with nothing to stop it.
                    if granted, !fromHold || self.holdActive { self.beginRecording() }
                    else { self.startedByHold = false; self.status = .idle }
                }
            }
        default:
            status = .idle   // denied — enable in System Settings › Privacy › Microphone
        }
    }

    private func beginRecording() {
        audio.clear()
        // Use a fresh engine each time. A long-lived engine caches the input
        // hardware format, so after the audio device changes (HDMI/TV, a headset,
        // Bluetooth) its inputNode reports a stale format; installTap would then
        // throw an Obj-C exception Swift can't catch, aborting the app.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No usable input device leaves the format at 0 Hz / 0 channels, which
        // also makes installTap throw — bail out gracefully instead of crashing.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .idle
            return
        }
        recordRate = format.sampleRate
        let sink = audio   // capture the Sendable buffer, not self
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            sink.append(from: buffer)
        }
        do { try engine.start(); status = .recording }
        catch { input.removeTap(onBus: 0); status = .idle }
    }

    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let raw = audio.take()
        guard !raw.isEmpty else { status = .idle; return }

        // Load the model first (shown as .loading, or .downloading if it must be
        // fetched), then run the actual inference under .transcribing — so the
        // load phase is never mislabelled as "transcribing".
        status = .loading
        let samples = Self.resample(raw, from: recordRate, to: Self.targetRate)
        let model = settings.voiceModel
        let language = settings.voiceLanguage == "auto" ? nil : settings.voiceLanguage
        let translate = settings.voiceTranslate
        Task { [weak self] in
            let ready = await Transcriber.prepare(model: model) { fraction in
                DispatchQueue.main.async {
                    self?.downloadProgress = fraction
                    self?.status = fraction < 1.0 ? .downloading : .loading
                }
            }
            guard ready else { DispatchQueue.main.async { self?.status = .idle }; return }

            DispatchQueue.main.async { self?.status = .transcribing }
            let text = await Transcriber.transcribe(samples, model: model,
                                                    language: language, translate: translate) { _ in }
            DispatchQueue.main.async {
                if !text.isEmpty {
                    if let note = Self.noteBody(from: text) {
                        self?.todo.add(note)          // "заметка …" → Tasks tab
                    } else {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                }
                self?.status = .idle
            }
        }
    }

    /// If the transcript opens with a "note" keyword, return the text after it —
    /// that goes to the Tasks list instead of the clipboard. `nil` means ordinary
    /// dictation. Case-insensitive; a letter/digit right after the keyword (e.g.
    /// "notebook") is not a match. Longer phrases are checked first.
    static func noteBody(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for kw in ["новая заметка", "new note", "заметка", "заметку", "note"] {
            guard lower.hasPrefix(kw) else { continue }
            let rest = trimmed[trimmed.index(trimmed.startIndex, offsetBy: kw.count)...]
            if let first = rest.first, first.isLetter || first.isNumber { continue }
            let body = String(rest).drop { " :,.-—".contains($0) }
            let result = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }
        return nil
    }

    /// Nearest-sample downsample to 16 kHz mono. Crude (no anti-alias filter) but
    /// good enough for Whisper; can be swapped for AVAudioConverter later.
    private static func resample(_ input: [Float], from: Double, to: Double) -> [Float] {
        guard from > 0, to > 0, abs(from - to) > 1 else { return input }
        let ratio = from / to
        let count = max(0, Int(Double(input.count) / ratio))
        var out = [Float](); out.reserveCapacity(count)
        var pos = 0.0
        for _ in 0..<count {
            out.append(input[min(Int(pos), input.count - 1)])
            pos += ratio
        }
        return out
    }
}

/// Selectable dictation models (short names glob to the WhisperKit repo folders).
/// Bigger = more accurate and more RAM. Downloaded once on first use.
enum VoiceModels {
    static let options: [(id: String, label: String)] = [
        ("tiny", "Tiny · ~75 MB · fastest, rough"),
        ("base", "Base · ~145 MB · light"),
        ("small", "Small · ~465 MB · balanced"),
        ("large-v3-v20240930_626MB", "Large v3 Turbo · ~626 MB · best (recommended)"),
    ]
    static let defaultModel = "large-v3-v20240930_626MB"

    /// Spoken-language choices. "auto" lets Whisper detect it (which can misread
    /// some languages — e.g. Russian — so an explicit pick is the reliable fix).
    static let languages: [(id: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"), ("ru", "Russian"), ("de", "German"), ("es", "Spanish"),
        ("fr", "French"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"),
    ]
    static let defaultLanguage = "auto"
}

enum Transcriber {
    /// Where WhisperKit keeps a model on disk (its default Hub download location).
    static func modelFolder(_ id: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(id)")
    }

    /// Whether a model is already downloaded — used to mark it in Settings and to
    /// preload it at launch without kicking off a download.
    static func isModelDownloaded(_ id: String) -> Bool {
        FileManager.default.fileExists(
            atPath: modelFolder(id).appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    #if canImport(WhisperKit)
    static func transcribe(_ samples: [Float], model: String, language: String?, translate: Bool,
                           onDownload: @escaping @Sendable (Double) -> Void) async -> String {
        await WhisperBackend.shared.transcribe(samples, model: model, language: language,
                                               translate: translate, onDownload: onDownload)
    }
    static func prepare(model: String, onDownload: @escaping @Sendable (Double) -> Void) async -> Bool {
        await WhisperBackend.shared.prepare(model: model, onDownload: onDownload)
    }
    static func unload(_ model: String) async {
        await WhisperBackend.shared.unload(model)
    }
    #else
    /// WhisperKit not linked yet — returns empty so the rest of the flow builds
    /// and runs. Add the dependency to enable real transcription.
    static func transcribe(_ samples: [Float], model: String, language: String?, translate: Bool,
                           onDownload: @escaping @Sendable (Double) -> Void) async -> String { "" }
    static func prepare(model: String, onDownload: @escaping @Sendable (Double) -> Void) async -> Bool { false }
    static func unload(_ model: String) async {}
    #endif
}

#if canImport(WhisperKit)
import WhisperKit

/// Isolated so the WhisperKit API surface lives in one place. An `actor` so a
/// launch-time preload and a user-triggered dictation can't load the model twice.
private actor WhisperBackend {
    static let shared = WhisperBackend()
    private var pipe: WhisperKit?
    private var loaded: String?

    /// Load the model unless it's already the live one. `true` once a usable
    /// pipeline is ready. If the model is already on disk, load straight from that
    /// folder (skipping the network Hub check); otherwise download it first.
    private func ensureLoaded(_ model: String,
                              onDownload: @escaping @Sendable (Double) -> Void) async -> Bool {
        if pipe != nil, loaded == model { return true }
        do {
            let folderPath: String
            if Transcriber.isModelDownloaded(model) {
                folderPath = Transcriber.modelFolder(model).path
            } else {
                let folder = try await WhisperKit.download(variant: model) { onDownload($0.fractionCompleted) }
                folderPath = folder.path
            }
            pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folderPath))
            loaded = model
            return true
        } catch {
            return false
        }
    }

    func prepare(model: String, onDownload: @escaping @Sendable (Double) -> Void) async -> Bool {
        await ensureLoaded(model, onDownload: onDownload)
    }

    /// Drop the loaded pipeline if it's this model (used when the model is deleted).
    func unload(_ model: String) {
        if loaded == model { pipe = nil; loaded = nil }
    }

    func transcribe(_ samples: [Float], model: String, language: String?, translate: Bool,
                    onDownload: @escaping @Sendable (Double) -> Void) async -> String {
        guard await ensureLoaded(model, onDownload: onDownload), let pipe else { return "" }
        // Explicit task/language: keep the spoken language (transcribe) unless the
        // user asked to translate to English, and force the language when set so
        // auto-detect can't mislabel it (e.g. Russian → English).
        let options = DecodingOptions(task: translate ? .translate : .transcribe, language: language)
        do {
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}
#endif
