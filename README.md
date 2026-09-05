<p align="center">
  <img src="Resources/AppIcon.png" width="150" alt="mac-notch logo" />
</p>

<h1 align="center">mac-notch</h1>

<p align="center">
  A lightweight, Dynamic-Island-style hub that lives right in your MacBook notch.<br/>
  Hover the notch and it expands; move away and it collapses. No Dock icon, no menu-bar icon.
</p>

<p align="center">
  <a href="https://github.com/timryadovouu/mac-notch/actions/workflows/build.yml">
    <img src="https://github.com/timryadovouu/mac-notch/actions/workflows/build.yml/badge.svg" alt="Build" />
  </a>
  <a href="https://github.com/timryadovouu/mac-notch/releases">
    <img src="https://img.shields.io/github/v/release/timryadovouu/mac-notch?include_prereleases&color=FA834D" alt="Latest release" />
  </a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Swift-5.9-FA834D?logo=swift&logoColor=white" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-3178C6" alt="SwiftUI + AppKit" />
  <img src="https://img.shields.io/badge/dependencies-none-2ecc71" alt="no dependencies" />
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license" />
</p>

---

## Overview

**mac-notch** turns the empty space around the camera notch into a small control
center. Everything is a module you jump between from a horizontal icon rail; the
coral gear opens a proper Settings window. It's a single Swift Package
executable — pure SwiftUI + AppKit, **no third-party dependencies**.

- Runs as an **accessory app** (`LSUIElement`) — invisible in the Dock and menu bar.
- Sits over the physical notch and morphs like the iPhone Dynamic Island.
- Works on notchless Macs and external displays too (a synthetic top-center notch).

## Modules

| Module | What it does |
| --- | --- |
| ⏱ **Timer** | Pomodoro with focus presets (5 / 10 / 15 / 25 / 30 / 60 min), a long break every 4 sessions. Configurable break lengths and a completion sound — pick any system sound (hover to preview) and choose whether it still plays during a Focus. A live countdown shows to the right of the notch; each phase change slides a **Focus / Break** alert in from the left. |
| 📋 **Buffer** | A persistent clipboard. Everything you copy is saved as a **real file** under the buffer folder, in a per-day `YYYY-MM-DD` subfolder — text, images, and any copied files. Click an entry to copy it back, or **drag it straight out** to Finder / any app. Per-row copy & delete on hover; "Finder" opens the folder, "Clear day" wipes today. Deletions made directly in the folder show up automatically. |
| 🎵 **Media** | Now-playing + transport for **Spotify** (AppleScript) and **cmus** (`cmus-remote`). Play/pause reacts instantly. While something plays, a little **equalizer** pulses to the left of the notch; pause it and a coral ⏸ takes its place. |
| ✅ **Tasks** | A local to-do list: add, complete, delete, restore. **Undone tasks stay on top, completed ones sink to the bottom.** Copy a task's text, or move it to a trash that keeps deleted items for a while. |
| ⏳ **Screen Time** | Local, on-device usage tracking: it credits the frontmost app every second and shows ranked apps (with icons), total time and switch count. **Each day is kept as its own snapshot — browse past days with ◀ / ▶**, and toggle a bar chart of the current week (Mon–Sun). Resets at midnight; history retention is configurable. |

The **Tasks, Buffer and Screen Time** panels have a little home-indicator grabber
at the bottom — tap it to grow the panel vertically (and again to shrink).

## Beside the camera

When the panel is open, the black areas either side of the lens show live
**system metrics**: **CPU** on the left (coral bar + %), **RAM** on the right
(used / total GB). RAM "used" is resident active + wired memory, matching
`htop` / `btop` rather than Activity Monitor's higher, compression-inclusive
figure. No tab, no clutter — just there while you're already looking.

## The collapsed strip

Even when closed, the brow stays useful:

- **Left** — a pulsing **equalizer** while music plays (a coral ⏸ when paused), or a
  brief coral flash on copy and a **Focus / Break** alert on a timer phase change.
- **Right** — the Pomodoro **countdown** while a timer runs, and a small pulsing
  **coral blob** whenever a Claude Code session is thinking (see below).

## Claude Code integration

Optional, off by default. Flip **Track Claude Code** in Settings and mac-notch
gives you two things:

- A pulsing **coral blob** on the right of the notch while any Claude Code
  session is actively working — it lights only between your prompt and Claude's
  stop, so it's a real "thinking now" indicator, not just "a session is open".
- As you approach a usage limit, a coral line in the Timer tab shows when it
  resets — **"Claude limits reset at HH:MM"** (or **"Claude will be ready at
  HH:MM"** when you're actually blocked) — and **"Claude is ready!"** once the
  window frees up. The reset time is read back from disk, so it survives quitting
  Claude.

**How it works.** Enabling the toggle merges a few [hooks](https://docs.claude.com/en/docs/claude-code/hooks)
and a `statusLine` command into `~/.claude/settings.json` (backed up to
`settings.json.bak` first; your other settings are preserved):

- The **hooks** append session events to `~/.claude/mac-notch/events.jsonl`; that
  stream drives the blob.
- The **reset time** comes from whichever Claude you use:
  - **Terminal Claude Code** — mac-notch installs *itself* as your `statusLine`
    (a hidden `mac-notch statusline` subcommand), the only place the CLI exposes
    when a window resets. Your terminal footer becomes a compact
    `Opus 4.8 · project · main · ctx 42% · 5h 63% · wk 21%`, and a **threshold**
    setting picks the usage % at which the line appears.
  - **Desktop app** — the chat never runs a statusLine, so mac-notch reads the
    reset time straight from the desktop app's own local storage instead
    (best-effort: it's undocumented and may change between Claude versions).

Everything stays local — nothing is sent anywhere.

## Settings

The coral **gear** toggles a standalone window:

- **General** — Launch at login, Track Claude Code, and the usage % at which the limit line appears.
- **Modules** — enable/disable and reorder the tabs in the rail.
- **Timer** — short/long break lengths, the end-of-session sound (any system sound, hover to preview), and whether it plays during a Focus.
- **Screen Time** — how long to keep daily history (default 1 year).
- **Buffer** — folder location, auto-clear age, or clear-at-end-of-day.
- **Notch** — reset-to-default-tab delay and which tab is the default.

## Install & run

Requires macOS 13+ and the Xcode command-line tools.

Grab a build from [Releases](https://github.com/timryadovouu/mac-notch/releases),
or build it yourself. For development:

```bash
swift run
```

Build a double-clickable app (generates the icon, packages `mac-notch.app`):

```bash
./build-app.sh
open mac-notch.app
```

> Unsigned build: the first launch may need **right-click → Open** to get past
> Gatekeeper.

Quit from the red **Quit** button in the expanded panel.

## Where data lives

Everything stays on your Mac:

- Clipboard buffer: `~/Library/Application Support/MacNotch/localBuffer/`
- Tasks, Screen Time, settings: `~/Library/Application Support/MacNotch/`
- Claude Code tracking (only if enabled): `~/.claude/mac-notch/`

When Claude tracking is on, mac-notch also **reads** (never writes) the reset
time from the desktop app's local storage; that data stays on your Mac too.

## Permissions

- **Media → Spotify** uses AppleScript, so macOS will ask for **Automation**
  access the first time — approve it or the track/controls won't work. **cmus**
  needs `cmus-remote` on your `PATH`. Nothing else requires special permissions.

## Project structure

```
Sources/MacNotch/
  main.swift / AppDelegate.swift      app entry (accessory policy, app icon, Edit menu)
  StatusLine.swift                    `mac-notch statusline` subcommand for Claude Code
  DesktopLimitReader.swift            reads the limit reset time from the Claude desktop app
  ScreenNotch.swift                   notch geometry (+ non-notch fallback)
  NotchController.swift               the window over the notch + hover logic
  NotchRootView.swift                 the brow, its morphing, equalizer & Claude blob
  ExpandedPanel.swift                 CPU/RAM header, icon rail + module hosting
  GrabberBar.swift                    shared grow/shrink pill
  *Panel.swift                        per-module UI
  PomodoroModel / BufferManager /
  MediaController / AppUsageTracker /
  TodoStore / SystemStats /
  ClaudeSessionsManager               module & integration logic
  Settings.swift / SettingsPanel.swift  settings model + window
Resources/AppIcon.png                 app icon source
build-app.sh                          release build → mac-notch.app
.github/workflows/                     CI: build on push, publish on version tags
```

## License

[MIT](LICENSE) © Timofei Ryadovoi

## Notes

Inspired by [macnotch.io](https://macnotch.io).
