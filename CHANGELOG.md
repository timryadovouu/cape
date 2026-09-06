# Changelog

All notable changes to mac-notch are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- The Claude 5-hour reset line in the Timer tab now shows as soon as you start
  using the window, rather than only past a usage threshold.

### Removed
- The usage-% threshold setting — the reset time is the same regardless of usage,
  and it isn't readable at all in the desktop app, so the slider was misleading.

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

[0.1.0-beta.2]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/timryadovouu/mac-notch/releases/tag/v0.1.0-beta.1
