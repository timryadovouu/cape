import Foundation

/// Terminal integration for zsh: `<command>; cape done` flashes ✓ / ✗ in the
/// notch when the command ends — and, with "Long commands" on, so does any
/// command that ran past a threshold while you were in another window.
///
/// `cape` is a zsh *function* (in `cape.zsh`, sourced from ~/.zshrc), so it sees
/// the exit status of the command before it, and a preexec hook times it. It
/// reports by dropping a small JSON file into `shell/`, which Cape watches —
/// no process launched, nothing to route when several Cape copies exist.
final class ShellIntegration {
    struct Done {
        let ok: Bool
        let command: String
        let seconds: Int
        let auto: Bool        // from the long-command hook, not an explicit `cape done`
        let app: String?      // the terminal's bundle id
    }

    /// Called on the main queue for each finished command.
    var onDone: ((Done) -> Void)?

    static var support: URL { AppModules.supportDirectory }
    static var script: URL { support.appendingPathComponent("cape.zsh") }
    static var conf: URL { support.appendingPathComponent("shell.conf") }
    static var inbox: URL { support.appendingPathComponent("shell", isDirectory: true) }
    static var zshrc: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc") }

    private static let marker = "# Cape shell integration"
    private static var sourceLine: String {
        "[[ -r \"$HOME/Library/Application Support/Cape/cape.zsh\" ]] && "
            + "source \"$HOME/Library/Application Support/Cape/cape.zsh\"  \(marker)"
    }

    private let settings: Settings
    private var source: DispatchSourceFileSystemObject?
    private var subs: [Any] = []

    init(settings: Settings) {
        self.settings = settings
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.inbox, withIntermediateDirectories: true)
        try? Self.zsh.write(to: Self.script, atomically: true, encoding: .utf8)
        // Reports left while Cape wasn't running are old news.
        for file in (try? fm.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
        subs.append(settings.$shellAuto.sink { [weak self] _ in DispatchQueue.main.async { self?.writeConf() } })
        subs.append(settings.$shellAutoSeconds.sink { [weak self] _ in DispatchQueue.main.async { self?.writeConf() } })
        watch()
    }

    // MARK: - ~/.zshrc

    var isInstalled: Bool {
        (try? String(contentsOf: Self.zshrc, encoding: .utf8))?.contains(Self.marker) ?? false
    }

    /// Append the `source` line to ~/.zshrc (backed up first).
    func install() throws {
        var text = (try? String(contentsOf: Self.zshrc, encoding: .utf8)) ?? ""
        guard !text.contains(Self.marker) else { return }
        if !text.isEmpty {
            try? text.write(to: Self.zshrc.appendingPathExtension("cape-backup"), atomically: true, encoding: .utf8)
        }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n" + Self.sourceLine + "\n"
        try text.write(to: Self.zshrc, atomically: true, encoding: .utf8)
    }

    func uninstall() throws {
        guard let text = try? String(contentsOf: Self.zshrc, encoding: .utf8), text.contains(Self.marker) else { return }
        let kept = text.components(separatedBy: "\n").filter { !$0.contains(Self.marker) }
        try kept.joined(separator: "\n").write(to: Self.zshrc, atomically: true, encoding: .utf8)
    }

    // MARK: - Settings for the shell

    private func writeConf() {
        let text = "CAPE_AUTO=\(settings.shellAuto ? 1 : 0)\nCAPE_MIN=\(settings.shellAutoSeconds)\n"
        try? text.write(to: Self.conf, atomically: true, encoding: .utf8)
    }

    // MARK: - Inbox

    private func watch() {
        let fd = open(Self.inbox.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func drain() {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let app = o["app"] as? String
            onDone?(Done(ok: (o["status"] as? Int ?? 0) == 0,
                         command: (o["cmd"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                         seconds: o["seconds"] as? Int ?? 0,
                         auto: (o["auto"] as? Int ?? 0) == 1,
                         app: app?.isEmpty == false ? app : nil))
        }
    }

    // MARK: - The zsh side

    private static let zsh = #"""
    # Cape shell integration — written by Cape on every launch (edits are overwritten).
    #   <command>; cape done    ✓ / ✗ in the notch when the command ends
    #   Settings › Terminal › "Long commands"    the same after any long command,
    #                                            while you're in another window
    [[ -o interactive ]] || return 0
    zmodload zsh/datetime 2>/dev/null || return 0
    zmodload -F zsh/files b:zf_mv 2>/dev/null
    typeset -g _cape_dir=${0:A:h}
    typeset -g _cape_start=0 _cape_cmd='' _cape_sent=0

    _cape_preexec() { _cape_start=$EPOCHREALTIME; _cape_cmd=$1; _cape_sent=0 }

    # _cape_send <exit status> <seconds> <auto: 0|1>
    _cape_send() {
      [[ -d $_cape_dir/shell ]] || return 0
      local cmd=${_cape_cmd%;*cape done*}
      while [[ $cmd == *' ' ]]; do cmd=${cmd% }; done
      cmd=${cmd//\\/\\\\}; cmd=${cmd//\"/\\\"}; cmd=${cmd//$'\n'/ }; cmd=${cmd//$'\t'/ }
      cmd=${cmd[1,120]}
      local f="$_cape_dir/shell/$EPOCHREALTIME-$$"
      print -r -- "{\"status\":$1,\"seconds\":$2,\"auto\":$3,\"app\":\"$__CFBundleIdentifier\",\"cmd\":\"$cmd\"}" >| "$f.part"
      if (( $+builtins[zf_mv] )); then zf_mv "$f.part" "$f.json"; else command mv "$f.part" "$f.json"; fi
    }

    cape() {
      local s=$?
      if [[ $1 == done ]]; then
        local secs=0
        (( _cape_start > 0 )) && secs=$(( EPOCHREALTIME - _cape_start ))
        _cape_send $s ${secs%.*} 0
        _cape_sent=1
      else
        print -u2 'usage: <command>; cape done'
      fi
      return $s
    }

    _cape_precmd() {
      local s=$?
      (( _cape_start > 0 )) || return 0
      local secs=$(( EPOCHREALTIME - _cape_start ))
      _cape_start=0
      (( _cape_sent )) && return 0
      [[ -r $_cape_dir/shell.conf ]] && source $_cape_dir/shell.conf
      (( ${CAPE_AUTO:-0} )) || return 0
      (( secs >= ${CAPE_MIN:-30} )) || return 0
      local -a words=(${(z)_cape_cmd})
      case ${words[1]:t} in
        vi|vim|nvim|nano|emacs|micro|hx|ssh|mosh|claude|less|more|man|top|htop|btop|cmus|tmux|screen|watch|tail|fzf|lazygit|tig)
          return 0 ;;
        python|python3|node|irb|ipython|psql|mysql|sqlite3|bash|zsh|sh|fish)
          (( ${#words} > 1 )) || return 0 ;;   # a bare REPL / shell, not a task
      esac
      _cape_send $s ${secs%.*} 1
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _cape_preexec
    add-zsh-hook precmd _cape_precmd
    """#
}
