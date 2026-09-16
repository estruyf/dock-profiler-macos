# Changelog

All notable changes to Dock Profiler are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
