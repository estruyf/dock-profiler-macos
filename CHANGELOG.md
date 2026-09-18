# Changelog

All notable changes to Dock Profiler are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The AI Usage widget picks up a new sign-in by itself. While a card says
  "Sign-in expired" or "Not signed in", the widget re-reads the service's
  credentials every 20 seconds instead of waiting for the five-minute refresh or a
  click, and asks the API again only once the token differs from the one it refused.

## [1.4.0] - 2026-09-17

### Added

- **About section** at the bottom of Settings: the app's icon, its version and
  build number, and links to GitHub, the changelog and the issue tracker. The
  copy button beside the version puts it on the clipboard together with the
  macOS version, ready for a bug report.

## [1.3.0] - 2026-09-17

### Added

- **AI Usage widget.** What is left of your **Claude** and **GitHub Copilot**
  allowances, a card per service, drawn as numbers, rings or bars — pick the
  layout and the services on its card in the editor. Each card shows the
  tightest of the service's main windows (Claude's 5-hour and weekly limits,
  Copilot's premium requests for the month), turning orange under a quarter
  and red under a tenth. Click a card for every window with its reset time
  and countdown, Claude's per-model weekly limits included; refresh or open
  the service's usage page from the context menu. Nothing to sign in to: it
  reads Claude Code's token from the Keychain (`Claude Code-credentials`,
  which macOS asks about once) and the Copilot extensions' token from
  `~/.config/github-copilot`, and refreshes every five minutes while on
  screen and when the Mac wakes. Tokens are only read, never refreshed, so
  Claude Code stays signed in.
- Stacks can show a ring beside an item, for what is left of an allowance.
- **AirDrop widget.** Drop files on it and the AirDrop picker opens with them;
  click it for Finder's AirDrop window.
- **Dock looks.** The custom dock's slab can follow the system, as before; keep
  a light or dark look whatever the system appearance — its tiles, tips and
  stacks follow; be drawn as **Liquid Glass** on macOS Tahoe; or go away
  altogether, leaving each widget on its own card. The slab can blur what is
  behind it or be solid — clear, for Liquid Glass — and is solid while macOS's
  Reduce transparency is on; it can
  take a wash of the profile's colour, drop the cards behind widgets, and pack
  its tiles at one of three densities. All on the profile's Custom Dock tab.
  Liquid Glass and transparent docks read the wallpaper under them and go
  light or dark to suit it, as the Tahoe Dock does, so white tiles never sit
  on a white desktop; clear glass is dimmed a little towards the slab's shade,
  so its tiles read over a window of any colour too.

## [1.2.0] - 2026-09-17

### Added

- **Custom dock.** A profile can now carry a dock of Dock Profiler's own,
  drawn in a floating panel that never takes focus. Either **apps and
  widgets** together — the profile's apps, with widgets dragged in among them
  in the editor's preview, standing in for the macOS Dock, which is parked out
  of the way while the profile is active and put back afterwards — or
  **widgets only**, a strip beside the macOS Dock. It goes on any edge (bottom
  or top, left, centre or right; or left or right, centred), can show apps that
  are open but not pinned, can hide until the pointer reaches its edge — leaving
  a slim mark on the edge, if you like, so you know it is there — has a size
  slider, and can magnify tiles under the pointer. In a column the widgets
  become icon-sized tiles and re-flow to fit, and every tile has a hover tip
  with its detail.
- **Widgets.** Clock, date and battery, plus:
  - **Agents** — what the Claude Code sessions tracked by
    [Agent Frame](https://github.com/estruyf/vscode-agent-frame) are doing —
    working, waiting, idle — as a card per session in Agent Frame's colours,
    read from its session files. Click a card to bring the editor window
    hosting that session forward. Or fold them into **one tile** with a count
    that opens into the list.
  - **Now Playing** — the track in Music or Spotify, with its album art.
    Click to play or pause; skip from the context menu, or turn on previous
    and next buttons on the widget's card. Track changes arrive over
    distributed notifications; the first read, the artwork and the controls
    use Apple Events, so macOS asks once whether Dock Profiler may control the
    player.
  - **Profiles** — the active profile, opening into the list to switch to
    another one without going to the menu bar.
  - **Trash** — the can, full or empty. Click to open it, drop files on it to
    delete them, empty it from the context menu.
  - **Folder** — a folder that opens into its most recent files, like a Dock
    stack. Downloads by default; choose any folder on its card in the editor.
  - **App Stack** — several apps folded into one tile, a grid of their icons,
    opening into the apps themselves. Add apps on its card or drop them from
    Finder.
  Stacks open in a panel beside the dock that closes on a click anywhere else,
  and — like the dock — never takes focus from the front app.

### Changed

- Profiles saved by an older version now load with defaults for any field
  added since, instead of the whole store failing to decode.
- **Items can be reordered in the list too**, by dragging a card; the others
  shuffle aside and the Dock preview above follows, since both edit the same
  row. (It is a gesture like the live dock's rather than a system drag, because
  on macOS drop targets inside a scrolled list are hit-tested where they were
  before scrolling — cards further down, where the widgets tend to sit, never
  took a drop.)
- **A widget can sit on either side of a spacer.** Widgets keep their place by
  anchoring to the app before them, and a spacer has no path to anchor to, so
  a widget after a spacer used to jump back in front of it. Spacers between
  the app and the widget are counted now, so `App · Spacer · Widget` and
  `App · Widget · Spacer` both stay as arranged.
- **Widgets appear in the Items list** when the custom dock is combined, in
  among the apps as the dock shows them, so the whole row can be arranged and
  trimmed from one place. Their settings stay on the Custom dock tab.
- **The custom dock can be rearranged in place**, the Dock's way: hold a tile
  or widget for a moment, drag it along the dock, let go. The others shuffle
  aside as it passes and the profile is updated, so there is no need to open
  the editor for a quick reorder. A plain click still opens the tile.
- **A combined custom dock shows up in Mission Control**, drawn just above the
  macOS Dock's own window level — the one level Mission Control leaves on
  screen — and in front of the parked Dock, which Mission Control draws
  regardless of auto-hide. A widgets-only strip stays at the ordinary floating
  level, below a live Dock that must still be able to slide over it. A custom
  dock set to hide until the pointer reaches its edge comes out for Mission
  Control, as the Dock does, and hides again afterwards — nothing announces
  Mission Control, so the pointer poll that runs while the dock is hidden
  watches for the screen-sized window the Dock process puts up for it.
- **Tooltips are centred on their tile and sit clear of the dock.** They
  anchor on the tile's own frame, above the dock's panel — which includes the
  room magnified tiles grow into — rather than on the pointer, so they no
  longer overlap a tile, magnified or not, and do not wander with the pointer.
- **Finder can be added in one click.** The Dock shows Finder without it being
  pinned, so a captured profile never has it and a combined custom dock —
  which has no Finder of its own — went without unless you dug it out of
  `/System/Library/CoreServices`. The arrow beside **Add app…** now offers
  Finder, pinned at the front as the Dock has it. It is left out when a profile
  is written to the macOS Dock, which would otherwise show two.
- **An app dragged from Finder can be dropped anywhere on the Dock preview**,
  and lands where it was dropped. Before, only the empty space past the `+`
  took the drop; the tiles themselves swallowed it as an attempted reorder.

## [1.1.3] - 2026-09-16

### Fixed

- **⌫ still did not remove the selected item.** 1.1.2 handed keyboard focus
  to the Dock preview with SwiftUI's `focusable()`, which on macOS only works
  when "Use keyboard navigation to move focus between controls" is switched on
  in System Settings. The editor now listens for the keys itself: with an item
  selected, **⌫** and forward delete remove it and **⎋** clears the selection.
  Typing in a text field is never intercepted.

## [1.1.2] - 2026-09-16

### Fixed

- **Spacers could not be selected in the Dock preview.** A spacer is drawn as
  a dashed outline, and only that hairline took the click. The whole tile now
  does.
- **⌫ did not remove the selected item.** Nothing in the editor ever took
  keyboard focus, so the key never reached it. Clicking a tile in the preview,
  or a card in the Items list, now focuses the preview: **⌫** removes the
  selection and **⎋** clears it.
- **Dragging a tile to reorder it did nothing.** Each tile was a button, which
  claimed the mouse-down before a drag could begin. Tiles drag again, and one
  let go between tiles no longer stays dimmed.

## [1.1.1] - 2026-09-03

### Fixed

- **A black line ran across the profile manager's header.** AppKit ruled its
  titlebar separator straight through the toolbar that names the profile. The
  window now draws no separator at all.
- **The pane jumped when you moved between Settings and a profile.** Settings
  put nothing in the toolbar, so the titlebar shrank from 52 to 28 points and
  the top of the pane — scrollbar included — moved with it. Settings now names
  itself in the header the way a profile does, and both keep the same height.

## [1.1.0] - 2026-09-03

### Changed

- **Settings moved into the profile manager**, as the last row of the sidebar:
  select it and the settings open in the pane beside the profiles, instead of
  in a window of their own. Reachable from the menu bar's `Settings…`, or with
  `⌘,` while the manager has focus.
- **"Show the active profile name in the menu bar" is now "Use the active
  profile's icon in the menu bar"**, which is what the toggle always did — a
  menu bar item shows the glyph and drops the title. Your existing preference
  carries over.

### Removed

- **Switching desktops.** A profile no longer jumps to a Space when it is
  activated: macOS has no API for it, so it meant posting `Control + ←/→`
  keystrokes and asking for Accessibility access to do something the Dock
  profile itself never needed. The wallpaper half is unchanged — it lands on
  whichever desktop you are on. **Dock Profiler now asks for no privacy
  permissions at all**, and Settings no longer has a Desktops section.

### Fixed

- **The window title no longer sits across the profile manager's toolbar.**
  SwiftUI re-showed it whenever the detail pane changed, on top of the toolbar
  that already names the profile.

## [1.0.1] - 2026-09-03

### Fixed

- **The menu bar panel washed out over light wallpapers.** It now uses the same
  blurred, tinted background as the Quick Switcher, so the panel stays legible
  regardless of what's behind it.

## [1.0.0] - 2026-09-03

First release.

### Added

- **Dock profiles.** Save the apps and spacers pinned to your Dock as a named,
  coloured, glyph-tagged profile, and switch between them from the menu bar in
  one click. Only pinned apps change by default — folders, stacks, running
  apps, and every other Dock setting are left exactly as they are. A profile
  can optionally also manage the folders/files side of the Dock, and its own
  position, size, magnification, auto-hide, recents and minimize-into-icon
  settings.
- **An optional desktop per profile.** Since macOS has no API to create or
  rename a Space, a profile instead switches to a Space you've already made in
  Mission Control (by number, using either `Control + ←/→` or `Control +
  <number>`) and can set the wallpaper on the desktop it lands on.
- **A Dock you edit like a Dock.** The profile editor renders your Dock as a
  Dock — drag to reorder, drop an app in from Finder, right-click or ⌫ to
  remove — with a plain-language sentence spelling out exactly what activating
  the profile will and won't touch.
- **A Spotlight-style quick switcher.** A global shortcut (⌥⌘D by default,
  changeable) opens a searchable list of profiles anywhere: type to filter,
  arrow keys or ⌘1–9 to pick one, ↵ to activate. Registered through Carbon, so
  it needs no Accessibility permission.
- **A `dockprofiler://` URL scheme** for driving the app from Raycast, Alfred,
  Shortcuts, Keyboard Maestro or a script — `switch`, `profiles`, `welcome`,
  and `activate` by name or id.
- **Auto-save.** The profile you last activated tracks the Dock: drag an app
  in or out by hand and the profile updates to match, so the saved profile
  never drifts from what you're actually using.
- **A one-screen first run.** No tour, no carousel — save the Dock you have
  now as your first profile, or skip it.
- Local storage only. No account, no sync, no analytics — profiles live in
  `~/Library/Application Support/Dock Profiler/profiles.json`.
- A universal (Apple Silicon and Intel), signed and notarized build, and a
  Homebrew cask: `brew install --cask estruyf/tap/dock-profiler`.
