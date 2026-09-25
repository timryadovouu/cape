import AppKit

// Hidden `cape statusline` subcommand: read Claude Code's statusLine JSON
// from stdin, capture the usage-limit reset times, print a footer, and exit —
// before any GUI is created.
if CommandLine.arguments.dropFirst().first == "statusline" {
    StatusLine.run()
    exit(0)
}

// Hidden `cape permission` subcommand: Claude Code's PermissionRequest hook —
// hands the request to the running Cape and waits for Allow / Deny.
if CommandLine.arguments.dropFirst().first == "permission" {
    PermissionHook.run()
    exit(0)
}

// Dev tool: README screenshots from demo data (see Screenshots.swift). Refuses
// to run against the real data folder.
if Screenshots.outputDir != nil {
    guard ProcessInfo.processInfo.environment["CAPE_SUPPORT_DIR"] != nil else {
        print("CAPE_SCREENSHOTS needs CAPE_SUPPORT_DIR (a throwaway data folder)")
        exit(1)
    }
    Screenshots.seedDemoData()
}

// Accessory-приложение: без иконки в Dock и без пункта в меню-баре.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
