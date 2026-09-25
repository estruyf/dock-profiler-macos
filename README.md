# Dock Profiler

**One Dock per way of working.** Save the Dock you have as a profile, set up another
for writing, one for meetings, one for the side project — and switch between them in
one click, from the menu bar or with a keyboard shortcut. Give each profile its own
wallpaper, and the desktop you are on changes with it.

Everything is local. No account, no sync, no analytics.

![The profile manager](docs/screenshots/manager.png)

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask estruyf/tap/dock-profiler
```

Or download the disk image from the [latest release](../../releases/latest) and drag
Dock Profiler to Applications.

Needs macOS 14 or later. The build is universal (Apple Silicon and Intel), signed and
notarized. Want to build it yourself? See [Building](docs/development.md).

## First run

![The welcome screen](docs/screenshots/welcome.png)

Dock Profiler lives in the menu bar, not the Dock. On first launch it offers to save
the Dock you already have as your first profile — one screen, one button. Skipping is
fine; nothing about your Dock changes either way.

From there, open the profile manager from the menu bar icon and click **New** to set
up another profile. Each one starts from a copy of your current Dock; right-click a
profile in the sidebar to **Duplicate** it, or to **Capture current Dock** into it
after you have rearranged things by hand.

## Switching

![The menu bar](docs/screenshots/menubar.png)

- **Menu bar** — click the icon and pick a profile.
- **Quick switcher** — press **⌃⌥D** anywhere and a Spotlight-style window opens:
  type a few letters, `↵` to activate. `⌘1`–`⌘9` jump straight to a profile.

  ![The quick switcher](docs/screenshots/switcher.png)
- **From anything else** — Raycast, Alfred, Shortcuts, a shell alias:
  `open "dockprofiler://activate?name=Development"`. More in
  [Automation](docs/automation.md).

Switching only touches what the profile claims. Running apps, minimized windows and
every Dock setting the profile leaves alone stay exactly as they are.

## What a profile holds

- **Pinned apps and spacers** — always.
- **Folders, files and stacks** — the right side of the Dock, off by default.
- **Dock appearance** — position, size, magnification, auto-hide, recents.
- **Wallpaper** — set on the desktop you are on when you activate the profile, so
  "the development desktop" can look different from the others.
- **A custom dock** — Dock Profiler's own dock, with widgets. See below.

Each part is a tab in the editor, with a dot when it is switched on, and a sentence at
the top spelling out exactly what activating the profile will do.

### Editing

The editor shows your Dock as a Dock. Drag icons to reorder, drop an app in from
Finder to add it, right-click or press ⌫ to remove it.

### Auto-save

The profile you last activated tracks the Dock: drag an app in or out and the profile
is updated to match. Turn it off in Settings → Active profile if you would rather edit
by hand.

### Sharing

**Export…** in a profile's menu writes it to a `.dockprofile` file. Hand it to someone
and they import it with **Import…**, by dropping it on the sidebar, or by
double-clicking it in Finder. Profiles are made to travel: paths are rewritten for the
other user's home folder, apps installed somewhere else are found by their bundle id,
and anything missing is kept and marked so it fills in once installed.

## The custom dock

Nothing live can be pinned to the macOS Dock, so a profile can carry a dock of Dock
Profiler's own. Use it as a strip of widgets beside the real Dock, or let it stand in
for the Dock entirely — apps and widgets together, on any edge of any display, with
magnification, auto-hide and a Liquid Glass look on macOS Tahoe.

![The custom dock, standing in for the macOS Dock](docs/screenshots/custom-dock.png)

Widgets: **Clock**, **Date**, **Battery**, **Accessories** (AirPods, keyboard, mouse
and trackpad batteries), **Now Playing** (Music and Spotify),
**Profiles**, **Trash**, **AirDrop**, **Folder** (a stack of its newest files),
**App Stack**, **Launcher** (an app opened with arguments of your own — a browser as
one of its profiles — under an icon of your own), **Agents** (your running Claude Code
and Codex sessions, found by themselves, with
[Agent Frame](https://github.com/estruyf/vscode-agent-frame) filling in which of them
are waiting for you), **AI Usage** (how much of your Claude and GitHub Copilot
allowance is left, or how much you have used), and **Divider** (a line between groups).

Everything about it — positions, looks, each widget — is in
[The custom dock](docs/custom-dock.md).

## Permissions

None for the core: Dock profiles, wallpaper and the shortcut work without
Accessibility, Screen Recording or Automation access. A few widgets talk to other apps
(Music, Spotify, Finder) or read protected folders, and notification badges and the
window list on the custom dock's tiles need Accessibility — macOS asks about each the
first time, and only if you use it. [Permissions and privacy](docs/permissions.md) lists every prompt and why.

## Learn more

| | |
| --- | --- |
| [The custom dock](docs/custom-dock.md) | Positions, looks and every widget |
| [Automation](docs/automation.md) | The `dockprofiler://` URL scheme, shortcuts and examples |
| [Permissions and privacy](docs/permissions.md) | What is asked for, and what is not |
| [How it works](docs/how-it-works.md) | What activation writes, where data lives, restoring your Dock |
| [Building and releasing](docs/development.md) | Build from source, source layout, the release pipeline |
| [Changelog](CHANGELOG.md) | What changed per version |

## License

[MIT](LICENSE) — © Elio Struyf.
