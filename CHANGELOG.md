# Changelog

All notable changes to Dock Profiler are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
