# Changelog

All notable changes to Cape are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.5.2] — 2026-10-02

### Added
- **Pick what you need on the first launch** — the welcome tour's last step
  lists the extras as switches: the Pomodoro timer and Screen Time (with battery
  use), and for developers Claude Code sessions, Ports and the terminal's
  `cape done`. Everything starts on; turn off what you don't need, or skip the
  tour to keep it all. The developer extras switch on only where they fit —
  Claude when Claude Code is installed, `cape done` when there's a `~/.zshrc`.
  People updating keep their settings.
- **A switch for Ports** — *Settings › Tools*.

### Changed
- **Switched off means not running.** A hidden Screen Time tab no longer
  counts time or battery in the background; with Claude tracking off its log
  isn't read at all; CPU / RAM are measured only while the notch is open; and
  turning the Pomodoro tab off stops a running timer. With Screen Time and
  Claude off, Cape sits idle with almost no wake-ups.
- **Dictation without a model says so** — the dictation keys used to start
  recording and then quietly download the model (~626 MB). Now a strip drops
  down from the brow — “Dictation needs a model” with a ⬇ button — and shows the
  download, then “Preparing the model…” (the first load compiles it for the
  Neural Engine, which took a silent while before), then “Ready”. A red ✕ in
  the island beside it puts it away for later — and while the model downloads,
  cancels the download (half-downloaded files are removed).
- **Cancel a model download** in *Settings › Voice* too.

## [0.5.1] — 2026-09-29

### Added
- **Pick the app icon** — *Settings › General › App icon*: *Monet* (the new
  default — willows and water lilies, with “cape” in coral), the *Classic* one,
  *Sunrise* or *Water Lilies*. It changes in Finder, Launchpad and Spotlight
  too, and comes back after an update.

### Changed
- **A new app icon, painted after Claude Monet** — and none of the icons has
  the notch cut out of the top any more.

## [0.5.0] — 2026-09-29

### Added
- **Battery use per app** — the ⚡ button in Screen Time shows how much of a full
  charge (today's, worn battery included) each app used that day (“Safari · 46m
  · 6.2%”), sorted by it, with the day's total, the category ring and the week
  chart in battery terms too. Every row shows both time and battery. **It adds
  up to what the battery really lost:** an app gets its own work — measured by
  macOS for every process once a minute, helpers counted for their app
  (Chrome's, VS Code's…) — plus the screen and the rest of the Mac while it was
  in front, as the iPhone does; time away (no input, the display or the Mac
  asleep) goes to “macOS”. Hover a figure for the split. Counts only time on
  battery by default, or all the time (*Settings › Screen Time*). Nothing like
  it in macOS itself.
- **Clawd waits for you** — when a Claude session finishes while you're in
  another app, Claude Code's little pixel critter takes the island's place and
  stays until you look: click him (straight to that session), pick it in the
  list, or switch to the app it runs in — then he leaves with a happy hop. He
  hops in with a wave, then every few seconds waves, stomps, blinks or hops;
  looks toward the cursor; stretches during a Pomodoro break. Waiting long, he
  dozes off (z z Z — hover to wake him); in the end he waves and walks home
  behind the camera — as he does when you quit that app. One Clawd per session,
  up to four side by side. In *Settings › Claude*: how long he waits (1 hour by
  default) and when he falls asleep (5 min) — or turn him off.
- **Russian interface** — the notch, Settings, flashes, dates and even the
  permission prompts. English stays the default; switch in *Settings › General ›
  Language* (Cape relaunches to change it).
- **Album cover in the music island** — while music plays, the island left of
  the camera can show the cover instead of the equalizer (*Settings › Notch*);
  ⏸ stays as it is, and without a cover it falls back to the equalizer.
- **Tips** in Settings — how to use the notch, the islands and the extras, on
  one page.
- **Welcome tour** — on the first launch the notch opens and walks through the
  real tabs one by one (each explained in a strip below — including that
  dictation starting with “note” / “заметка” goes to Tasks, time and all), then
  the islands around the camera (drawn) and a few switches for what to turn on.
  Run it again from *Settings › Tips*. People updating from an earlier Cape
  don't get it unasked.

### Changed
- **One red instead of four** — Quit, the CPU bar, the Pomodoro focus time,
  delete / stop buttons, an overdue task and a failed command now share the same
  red, beside the coral accent; they used to be four slightly different reds.
- **The app icon has a transparent background** — no more white square around
  it in Finder, in the welcome tour, or on GitHub's dark theme.
- **Lighter on the battery:**
  - the notch reacts to the mouse moving instead of checking the cursor 50
    times a second;
  - the music player is asked only when something can have changed — Spotify
    announces its changes itself, cmus is queried only while it runs (every 2 s
    playing, 6 s paused) — so with no player open, no process is launched at all
    (it used to be one every 1.5 s);
  - the pulsing Claude blob, the music equalizer, the ringing bell and the paused
    timer are plain repeating animations now — they used to redraw the whole
    notch every frame, about 15–20 % of a CPU core while one was showing (now
    ~3 %).
- **Ports** shows one row per process with all its ports (`9000–9004, 52055`)
  instead of a row per port, and recognizes **Jupyter kernels** — a notebook open
  in VS Code or Jupyter used to fill the list with six anonymous Python ports
  each. Kernels get no browser button, and stopping one warns that the notebook
  loses its variables.

### Fixed
- **The Claude island no longer keeps "thinking" after Claude finished.** The
  hook writes each event in pieces; when Cape read the log mid-line, that event
  was lost — a lost "finished" left the coral blob on for ten minutes, and no
  Clawd. Cape now reads whole lines only.

## [0.4.0] — 2026-09-25

### Added
- **Claude Code sessions in the notch** — hover the Claude island (right of the
  camera) and a list of your sessions drops down from the brow: what each is
  doing (working · waiting for you · asked a question · done), its title and
  your last prompt. **Click one to jump into it** — in the Claude app, straight
  into that session's conversation. Finished sessions leave the list once opened,
  or after 15 minutes; slide left from the island along the brow to open the
  full panel. The island is coral while Claude works and
  turns **amber** when a session waits for you.
- **Allow / Deny from the notch** — when Claude asks to run a tool, the request
  shows up in that list (`Bash  npm run db:migrate`) with Allow and Deny.
  Unanswered, it goes back to the terminal / app after a timeout you choose
  (1 minute by default, *Settings › Claude*). Works in the terminal and in the
  Claude app's Code tab.
- **`cape done`** — add `; cape done` to any command (`npm run build; cape done`)
  and the notch flashes ✓ or ✗ with the command and how long it took, with a
  sound. Optionally, the same after **any command longer than N seconds** while
  you're in another window (off by default, 30 s). One click installs it into
  zsh — *Settings › Terminal*.
- **Ports** (Tools) — the dev servers listening on this Mac: port, process,
  project folder, uptime, reachable from the LAN or not. Open one in the browser
  or stop it; *Show all* adds system services.
- **QR codes in copied images** — copy a screenshot (⌃⇧⌘4) or an image with a QR
  code and its link lands in the buffer as its own entry, right under the image.
  No screen-recording permission. Toggle in Tools and *Settings › Buffer*.
- **Reverse mouse wheel** (Tools) — flips a mouse wheel's scroll direction while
  the trackpad keeps natural scrolling (what Scroll Reverser does).
- **Screen Time by category** — a ring and a legend split the day into Work,
  Browsing, Social, Entertainment, Learning and Other, sorted automatically;
  click a category to list only its apps. App bars take the category's color.
- **Task card** — the 🔔 on a task opens a card over the list: edit the text,
  quick picks (in 1 h, 18:00, tomorrow 9:00, Monday 9:00), a calendar and a
  24-hour time. Enter saves, Esc closes.
- **Click the music island** to pause / play; rest on it a moment to open Media.

### Changed
- **Settings** has a sidebar of pages, like System Settings, in a resizable
  window that remembers its size and the last page. The hint on the Tools page
  opens *Settings › Tools* directly.
- The music, copy and Claude islands share one width, so the brow grows evenly
  on both sides — and the Claude island is easier to hover. With the Claude list
  open and nothing on the left, an empty island mirrors it, so the list stays
  centered on the camera.
- The Claude island stays lit through long turns, and comes back after Cape
  restarts mid-turn.

### Fixed
- **cmus covers** for albums ripped as one file with a cue sheet, for tracks in
  `Disc 1` / `CD2` folders, and for covers with an unusual file name.

## [0.3.3] — 2026-09-24

### Changed
- **Smoother open & close** — only the black shape morphs now; the content
  appears already in place instead of riding along, so nothing slides sideways
  when a side island (music, timer, Claude…) is showing, and the paused ⏸ is back
  the moment the panel closes.

### Fixed
- The brow is centered on the physical notch (not the screen's middle, which can
  be half a point off) and no longer pokes past the cutout's edge.
- **Check for Updates** no longer fails with *"Couldn't read the latest release
  from GitHub"* once GitHub's API limit (60 requests an hour per IP — easy to hit
  on a VPN) is used up: the check now follows the plain release links, and the
  release notes load when available.

## [0.3.2] — 2026-09-24

### Added
- A short **Russian README** (`README.ru.md`) — the highlights, install, updates
  and what the signing means — with an English · Русский switch on both READMEs.

### Fixed
- The updater now removes the downloaded archive before relaunching (it used to
  leave a ~3 MB zip behind in the temporary folder).

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

[0.5.2]: https://github.com/timryadovouu/cape/releases/tag/v0.5.2
[0.5.1]: https://github.com/timryadovouu/cape/releases/tag/v0.5.1
[0.5.0]: https://github.com/timryadovouu/cape/releases/tag/v0.5.0
[0.4.0]: https://github.com/timryadovouu/cape/releases/tag/v0.4.0
[0.3.3]: https://github.com/timryadovouu/cape/releases/tag/v0.3.3
[0.3.2]: https://github.com/timryadovouu/cape/releases/tag/v0.3.2
[0.3.1]: https://github.com/timryadovouu/cape/releases/tag/v0.3.1
[0.3.0]: https://github.com/timryadovouu/cape/releases/tag/v0.3.0
[0.2.0]: https://github.com/timryadovouu/cape/releases/tag/v0.2.0
[0.1.3]: https://github.com/timryadovouu/cape/releases/tag/v0.1.3
[0.1.2]: https://github.com/timryadovouu/cape/releases/tag/v0.1.2
[0.1.1]: https://github.com/timryadovouu/cape/releases/tag/v0.1.1
[0.1.0]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0
[0.1.0-beta.2]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/timryadovouu/cape/releases/tag/v0.1.0-beta.1
