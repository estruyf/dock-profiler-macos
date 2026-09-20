# Changelog

All notable changes to Dock Profiler are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2026-09-20

### Added

- **The Dock's menu on the custom dock's app tiles.** Right-click an app and
  its open windows are listed, across every instance — a check mark on the one
  in front, a diamond on a minimized one — and choosing one brings it forward,
  which is the way to a particular window when an app has several. Below them,
  as in the Dock: Options with Keep in Dock (for a running app after the
  divider) and Show in Finder, then Show All Windows, Hide and Quit. Remove
  from Dock and Custom Dock Settings… now come first in every tile's menu,
  widgets included, so a long window list never pushes them out of reach. The window
  list is read through Accessibility, the same permission as the badges; until
  it is granted the menu has a **Show Windows Here…** item that leads to it.
  Recent documents are the one thing the Dock's menu has that this one cannot:
  macOS hands an app's list to that app alone.
- **Open at login on the welcome screen.** The same toggle as in Settings, on
  the screen a first run sees.

## [1.6.0] - 2026-09-20

### Added

- **Widget settings in the context menu.** Right-click a widget on the dock
  and its settings are there — the folder a stack opens, adding or removing
  apps in a stack, a layout, the services AI Usage tracks, what the
  Accessories widget shows — the same ones as on its card in the editor, so
  the dock can be set up without leaving it.
- **Accessories widget.** The batteries of your AirPods and their case, Magic
  Keyboard, mouse and headphones on the custom dock, a tile per device with its
  icon inside a green ring that empties with it — red when it is about to run
  out, a bolt while it charges — the way Notification Centre's Batteries widget
  draws them. Apple's accessories report their charge to macOS itself; others,
  like a Logitech mouse, over the Bluetooth battery service, for which macOS
  asks once whether Dock Profiler may use Bluetooth. On its card choose the
  ring with or without its level, tick off the accessories you do not want,
  and tick **This Mac** to put the Mac's own battery among them. Click for
  Bluetooth settings.
- **Notification badges on the custom dock's app tiles.** A combined dock can
  show the Dock's own badges — WhatsApp's unread count, Mail's — on its tiles,
  pinned and running alike. Switch it on with **Show notification badges on
  app tiles** in the Custom Dock tab. There is no API for another app's
  badge, so they are read from the macOS Dock's tiles through Accessibility;
  the option is off until asked for, macOS prompts once, and the tab points to
  System Settings until access is granted.
- **Drag a running app into the custom dock to keep it.** With "Also show apps
  that are open but not in the profile" on, an app after the divider can be
  held and dragged across it, as in the Dock; let go anywhere before the
  divider and it joins the profile in that spot. Let go after the divider and
  it stays where it was.
- **Remove an app or widget from the custom dock in place.** Hold a tile and
  carry it off the dock — its slot closes and the tile shows "Remove" — and let
  go; or right-click it and choose **Remove from Dock**. Both take it out of
  the profile. Widgets with no menu of their own — clock, date, battery,
  agents, app stack — now have one, with Remove and the dock's settings.
- **Permissions on the welcome screen and in Settings.** The welcome screen has
  an Accessibility card with an Allow button, so the one permission worth
  granting up front can be granted there; Settings gains a Permissions section
  that shows whether it is allowed and opens System Settings when it is not.

### Fixed

- **Clicking a running app's tile that had no window did nothing.** Apps such
  as Claude and WhatsApp keep running after their window is closed, so the
  tile's dot stays on — rightly — but a click only brought the app forward,
  with nothing to show. Tiles now open the app the way the Dock does, which
  makes it put its window back. The running dot also drops an app that is
  killed or crashes without the usual notification.

### Changed

- **AI Usage in orange.** The rings, bars and numbers are orange — red under a
  tenth, as before — instead of blue, and the ring is drawn flat, the same ring
  as the batteries', without the glow and gradient.
- **Settings moved to the bottom of the sidebar**, pinned under the profiles
  with the version beneath its name.
- **The switcher's default shortcut is ⌃⌥D.** It was ⌘⌥D, which is also
  macOS's shortcut for hiding the Dock — a hot key does not stop the system
  acting on it, so every press also brought the parked macOS Dock back from
  behind a combined custom dock. A saved ⌘⌥D is moved to ⌃⌥D, and Settings
  warns if ⌘⌥D is recorded again.

## [1.5.2] - 2026-09-20

### Changed

- **The README is for users now.** It covers what the app is, installing it,
  the first run, switching, what a profile holds and the custom dock, and
  links out for the rest. The detail moved into `docs/`: the custom dock and
  its widgets, automation with the `dockprofiler://` scheme, permissions and
  privacy, how activation works and where data lives, and building and
  releasing.
- **Screenshots of the custom dock**, as a row and as a column, rendered by
  the same script as the others. The profile manager shot is regenerated with
  a custom dock on the demo profile, so it shows the Custom Dock tab.

## [1.5.1] - 2026-09-20

### Fixed

- The AI Usage widget no longer reports "Not signed in" on a Mac that is
  signed in to Claude Code. The Keychain can hold more than one
  `Claude Code-credentials` item — an older sign-in, or one carrying only MCP
  server logins, left beside the current one — and the widget asked for a
  single match, so it could pick the stale one. It now reads every item,
  newest first, and uses the first with a live token.

## [1.5.0] - 2026-09-20

### Added

- **A dock on every display.** The custom dock's Position section has a
  **Displays** choice: the main display, as before, or all of them, each with a
  dock of its own. Every display takes the profile's edge and alignment unless
  it is given a position of its own on its row underneath — so two displays
  side by side can keep their docks on the outer edges, leaving the edge between
  them clear for the pointer to cross. Positions are kept by the display's own
  id, so a display keeps its place when it is unplugged and plugged back in;
  a display plugged in later takes the shared position until it is given one.
  Each dock hides, reveals and leaves its edge mark on its own, and each reads
  the wallpaper under it for a glass or transparent look.
- **Custom Dock Settings…** in the dock's context menu. Right-click any tile,
  widget or the slab itself and the profile opens on its Custom Dock tab.
- **Export and import profiles.** **Export…** in a profile's menu — the ··· in
  the editor, or a right-click in the sidebar — writes it to a `.dockprofile`
  file to share. **Import…** under the sidebar's New button reads one back; so
  does dropping the file on the sidebar, or double-clicking it in Finder. A
  profile travels well: paths under the home folder go out as `~/…`, the
  Dock's per-Mac bookmarks are left behind, an app installed somewhere else
  on the other Mac is found by its bundle identifier — and any widget anchored
  to it follows — and a wallpaper that is not there is switched off with its
  path kept. Imported profiles get fresh ids and a name no other profile has.

## [1.4.1] - 2026-09-18

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
