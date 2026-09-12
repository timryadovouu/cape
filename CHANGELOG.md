# Changelog

All notable changes to mac-notch are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

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
  actively rendering), mac-notch falls back to the desktop app's current value —
  which matters when you use both terminal Claude Code and the desktop app.

## [0.1.0] — 2026-09-06

First stable release. mac-notch is a Dynamic-Island-style hub that lives over the
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

[0.2.0]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.2.0
[0.1.3]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.3
[0.1.2]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.2
[0.1.1]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.1
[0.1.0]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.0
[0.1.0-beta.2]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.0-beta.1
