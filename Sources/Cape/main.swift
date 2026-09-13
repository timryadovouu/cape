import AppKit

// Hidden `cape statusline` subcommand: read Claude Code's statusLine JSON
// from stdin, capture the usage-limit reset times, print a footer, and exit —
// before any GUI is created.
if CommandLine.arguments.dropFirst().first == "statusline" {
    StatusLine.run()
    exit(0)
}

// Accessory-приложение: без иконки в Dock и без пункта в меню-баре.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
