# Changelog

All notable changes to Cape are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.3.1] — 2026-09-24

The first update delivered through the in-app updater — install it from
*Settings › Updates* in 0.3.0.

### Changed
- The README badges now link to what they describe (macOS, Swift, SwiftUI,
  WhisperKit, the license).

## [0.3.0] — 2026-09-24

The first release under the **Cape** name, and the first that updates itself.

### Added
- **In-app updates** — *Settings › Updates* checks GitHub Releases (at launch,
  every few hours, or on demand), and *Install & Relaunch* downloads the new
  version, verifies its signature, swaps it in and restarts. A coral dot on the
  gear and a brief flash in the notch announce a new version.
- **Task reminders** — put a time in the task (*"в 15:00"*, *"через 20 минут"*,
  *"завтра в 9"*, *"at 3pm"*; 24-hour clock) or set a date & time with the 🔔
  button (quick picks: +1 h, 18:00, tomorrow 9:00). When due, a ringing bell
  slides out to the right of the notch with a sound; hover it to open Tasks.
  Tasks are grouped into Overdue / Today / Upcoming / No date / Done.
- **Tools** — a new ▦ page on the right of the rail, with a global shortcut for
  each tool (*Settings › Tools*, no extra permission):
  - **Pick color** — the system loupe; the hex goes to the clipboard and buffer.
  - **Clean keyboard** — locks all keys behind an overlay while you wipe it
    (Done button, auto-unlocks after 2 min, on sleep or screen lock).
- **Media** — cover art (Spotify; for cmus a `cover`/`folder` image in the album
  folder or art embedded in MP3/M4A), a coral progress bar with click/drag to
  seek, and a click on the right-hand time toggles *time left* ↔ *track length*.
- **Media keys for cmus** — F7 / F8 / F9 now control cmus, and its track appears
  in Control Center.
- **Hover the music island** (left of the notch) to open straight to Media —
  can be turned off in *Settings › Notch*.
- **Charging flash** — plug in the charger and a springing ⚡ fills a coral
  battery up to the current percent.
- **Dictation keys** — hold **🌐 Fn** or **right ⌥** to talk (walkie-talkie
  style), and choose the double-tap key: ⌥ (either side), right ⌥ or ⌃.
- **Buffer day headers** — Pinned / Today / Yesterday / date, and the copy time
  on every entry.

### Changed
- **Renamed to Cape** — app, bundle id (`io.cape.app`), data folder
  (`~/Library/Application Support/Cape`), Claude folder (`~/.claude/cape`) and the
  release asset (`Cape.zip`). Nothing is imported from mac-notch.
- **Signed with the project's own certificate** ("Cape Signing") instead of
  ad-hoc, so macOS permissions survive updates. Grant them once more after
  installing 0.3.0.
- The rail keeps tabs on the left and puts Tools, Settings and Quit on the right.

### Fixed
- Copied **files** now appear at the top of the buffer (ordered by copy time, not
  by the file's own modification date).
- Dictation no longer **crashes** when the audio device changes (HDMI/TV,
  headphones, Bluetooth) — or when there's no input device.
- Quitting **Spotify** (⌘Q) no longer relaunches it.
- The dictation keys kept working only until you clicked into the notch — they now
  work whichever app is focused.
- The media progress bar moves smoothly (no more small jumps back).

### Upgrading
From 0.2.0 or earlier (*mac-notch*), download `Cape.zip` once by hand. Every
update after this one is a click in Settings.

## [0.2.0] — 2026-09-13

### Added
- **Voice dictation** — a mic button in the Buffer tab transcribes speech to text
  fully on-device via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Neural
  Engine). Selectable model (Tiny → Large v3 Turbo, downloaded once and preloaded
  at launch) and spoken language, an optional translate-to-English, a
  *"note …"* / *"заметка …"* prefix that files the text as a task instead of the
  clipboard, and a global **double-⌥ Option** shortcut (needs Accessibility). The
  mic button shows recording / loading / transcribing state and stays disabled
  until a model is downloaded; models can be deleted from Settings.

### Fixed
- **Notch on external displays** — the brow is now pinned to the built-in (notch)
  screen and re-anchors whenever the display arrangement changes, so connecting an
  HDMI/TV or an extended monitor no longer strands it in the middle of the other
  screen.

### Changed
- Adds a single dependency, WhisperKit, for the on-device dictation.
- The sound picker (Timer / Claude) now matches the native menu pickers, with a ▶
  button to preview the selected sound.

## [0.1.3] — 2026-09-12

### Added
- **Buffer favorites** — ⭐ an entry (star / copy / delete on hover) to pin it to
  the top and keep it out of the day-rollover, retention, and *Clear day* cleanups
  (favorites live in a `_favorites` folder).
- **Pomodoro controls in the collapsed notch** — hover the running countdown to
  reveal inline **pause / next / cancel** without opening the panel; click the time
  itself to pause/resume, and a paused timer blinks. **Next** now chimes and slides
  in the *Focus / Break* alert; **Cancel** clears back to a fresh focus session.
- **Screen Time — "Apps shown"** — choose how many apps the list shows (top 5–20
  or all) instead of a fixed eight.
- **Claude finish sound** (opt-in) — play a system sound when the "thinking" blob
  clears, with its own sound picker, a Focus/DND toggle, a *mute while the Claude
  app is in front* toggle, and a note if it matches the Pomodoro sound.

### Fixed
- **Screen Time** no longer credits time spent at the lock screen or screensaver
  (`loginwindow`) as app usage.

## [0.1.2] — 2026-09-08

### Fixed
- Screen Time week chart: paging to a day in another week now moves the chart to
  that day's Monday–Sunday week (and loads its totals), instead of always showing
  the current week regardless of the selected day.

## [0.1.1] — 2026-09-06

### Fixed
- Claude limit line: a stale terminal `statusLine` snapshot no longer shadows the
  live desktop reset time. Once the terminal data goes stale (its session isn't
  actively rendering), Cape falls back to the desktop app's current value —
  which matters when you use both terminal Claude Code and the desktop app.

## [0.1.0] — 2026-09-06

First stable release. Cape is a Dynamic-Island-style hub that lives over the
MacBook notch — hover to reveal, no Dock or menu-bar icon, zero dependencies.

### Features
- **Timer** — Pomodoro with focus presets and phase alerts, a collapsed-brow
  countdown, and a chime you can pick from any system sound (hover to preview),
  with an option to keep it during a Focus.
- **Buffer** — a file-backed clipboard: everything you copy is saved as a real
  file in per-day folders, draggable straight out to Finder or any app.
- **Tasks** — a local to-do list with undone-on-top ordering and a trash.
- **Screen Time** — on-device, per-day usage snapshots with a Mon–Sun week chart.
- **Media** — now-playing and transport for Spotify and cmus, with collapsed-brow
  islands (an equalizer while playing, a coral pause when paused).
- **System metrics** — live CPU and RAM beside the camera; RAM "used" matches
  `htop`/`btop`.
- **Claude Code integration** (opt-in) — a pulsing coral blob while a session is
  thinking, and a Timer-tab line showing when your 5-hour usage window resets,
  read from the terminal `statusLine` or the desktop app's local storage.
- A standalone Settings window, Launch at login, and an MIT license.

### Notes
- Unsigned build — the first launch needs **right-click → Open** (Gatekeeper).
- The prebuilt download is **Apple Silicon only**; Intel Macs build from source.

## [0.1.0-beta.2] — 2026-09-06

### Added
- **System metrics beside the camera** — live CPU (left) and RAM (right) in the
  black areas next to the lens, shown while the panel is open.
- **Claude Code integration** (opt-in via *Track Claude Code*):
  - a pulsing coral blob on the notch while a session is actively thinking;
  - a Timer-tab line showing when a usage limit resets — read from the terminal
    `statusLine`, or, in the desktop app, from its local storage — plus
    *"Claude is ready!"* once the window frees up, and a configurable usage-%
    threshold for when the line appears.
- **Media islands** in the collapsed brow — an equalizer while music plays, a
  coral pause glyph when paused — with instant play/pause response.
- **Selectable end-of-session sound** — pick any system sound from a dropdown
  (hover to preview), and choose whether it still plays during Do Not Disturb.
- **MIT license** and expanded install instructions.

### Changed
- RAM "used" now reports resident active + wired memory, matching `htop` / `btop`
  instead of Activity Monitor's higher, compression-inclusive figure.
- The Screen Time week chart starts on Monday.
- Thicker CPU/RAM meters; the on-copy flash icon is coral.

### Removed
- The separate **System** tab — its metrics moved beside the camera.

## [0.1.0-beta.1] — 2026-09-05

Initial public beta.

### Added
- The notch hub itself: hover to reveal, Dynamic-Island-style morph, running as
  an accessory app with no Dock or menu-bar icon.
- **Timer** — Pomodoro with focus presets, phase alerts, and a collapsed-brow
  countdown.
- **Buffer** — a file-backed clipboard with per-day folders, drag-out, and a jump
  to Finder.
- **Tasks** — a local to-do list with undone-on-top ordering.
- **Screen Time** — on-device per-day usage snapshots with a week chart.
- A standalone **Settings** window, Launch at login, and GitHub Actions CI +
  releases.

[0.3.1]: https://github.com/timryadovouu/cape/releases/tag/v0.3.1
[0.3.0]: https://github.com/timryadovouu/cape/releases/tag/v0.3.0
[0.2.0]: https://github.com/timryadovouu/cape/releases/tag/v0.2.0
[0.1.3]: https://github.com/timryadovouu/cape/releases/tag/v0.1.3
[0.1.2]: https://github.com/timryadovouu/cape/releases/tag/v0.1.2
[0.1.1]: https://github.com/timryadovouu/cape/releases/tag/v0.1.1
[0.1.0]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0
[0.1.0-beta.2]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0-beta.1
