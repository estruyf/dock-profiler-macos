# Dock Profiler

A macOS app for **Dock profiles** — save a Dock layout, switch to it in one
click — with an optional **wallpaper** attached to each profile, set on the desktop you
are on when you activate it.

Everything is local. No account, no sync, no analytics.

![The profile manager](docs/screenshots/manager.png)

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask estruyf/tap/dock-profiler
```

Or download the disk image from the [latest release](../../releases/latest) and drag
Dock Profiler to Applications. The build is universal (Apple Silicon and Intel), signed
and notarized.

## Requirements

macOS 14 or later. Building it needs a Swift 6 toolchain (Xcode 16).

## Build & run

```sh
npm run build:debug   # quick local build, current architecture
npm run open
```

Either call `./Scripts/build_app.sh` directly, or through the `npm` scripts that wrap
it — same build either way:

| `npm run` | What it does |
| --- | --- |
| `build:debug` | Quick build, current architecture only |
| `build` | Universal build (`arm64` + `x86_64`), ad-hoc signed |
| `build:install` | Universal build, copied to /Applications and launched |
| `build:zip` / `build:dmg` | Universal build, also zipped / made into a disk image |
| `sign` | Zipped, signed with the Developer ID `CODESIGN_IDENTITY` finds |
| `notarize` | Signed, notarized and stapled — needs a stored `xcrun notarytool` profile |
| `release` | `notarize`, plus a disk image — what CI runs |
| `open` / `quit` | Launch / quit the built app |
| `screenshots` | Regenerate `docs/screenshots` (see below) |
| `clean` | Remove `.build` and `build` |

`./Scripts/build_app.sh` on its own produces a universal, ad-hoc signed build in
`build/`. See the header of the script for signing and notarization details.

The app is a menu bar item (`LSUIElement`), so it has no Dock icon. The profile manager
opens from the menu bar, or by opening the app again from Finder. Settings lives in that
window too, as the last row of the sidebar — from the menu bar panel, `Settings…` opens
the manager on it, and `⌘,` selects it while the window has focus.

## First run

![The welcome screen](docs/screenshots/welcome.png)

One screen, one button: Dock Profiler offers to save the Dock you already have as your
first profile. Skipping is fine — nothing about your Dock changes either way. It can be
reopened from Settings → General → Welcome screen, or with `open "dockprofiler://welcome"`.

## Switching profiles

Three ways, all doing the same thing:

* **Menu bar** — click the Dock Profiler icon and pick a profile.

  ![The menu bar](docs/screenshots/menubar.png)
* **Quick switcher** — press the global shortcut (**⌥⌘D** out of the box) anywhere and a
  Spotlight-style window opens: type a few letters, `↑`/`↓` or `⇥` to move, `↵` to
  activate, `⌘1`–`⌘9` to jump straight to one, `esc` to close. It closes as soon as it
  loses focus, appears on whichever desktop you are on, and follows the mouse to the
  display you are working on.

  ![The quick switcher](docs/screenshots/switcher.png)
  Change or clear the shortcut in Settings → Quick switcher. It is registered through
  Carbon's `RegisterEventHotKey`, so it needs no Accessibility access; if another app
  already owns the combination, Settings says so.
* **URL scheme** — for Raycast, Alfred, Shortcuts, Keyboard Maestro or a shell script:

  ```sh
  open "dockprofiler://switch"                    # toggle the quick switcher
  open "dockprofiler://profiles"                  # open the profile manager
  open "dockprofiler://activate?name=Development" # activate a profile by name
  open "dockprofiler://activate?id=<uuid>"        # …or by id
  ```

  macOS only knows about the scheme once it has registered the bundle. Launching the app
  once is normally enough; if not, `lsregister -f "build/Dock Profiler.app"` forces it.

## What a profile holds

| Part | What happens on activation |
| --- | --- |
| Pinned apps and spacers | Replaces `persistent-apps` in `com.apple.dock` |
| Folders, files, stacks *(optional)* | Replaces `persistent-others` — off by default, so that side of the Dock is left alone |
| Dock appearance *(optional)* | Position, size, magnification, auto-hide, recents, minimize-into-icon |
| Desktop wallpaper *(optional)* | Sets the desktop picture on the desktop you are on |

Spacers come in two sizes, regular and small. Flexible spacers are not offered — macOS
does not apply them reliably — though one already in a captured Dock is preserved as-is.

The editor puts your Dock on screen as a Dock: drag the icons to reorder, drop an app in
from Finder to add, right-click or press ⌫ to remove. Underneath, three tabs — **Items**,
**Dock**, **Desktop** — carry a dot when that part of the profile is switched on, and a
sentence at the top spells out exactly what activating it will do and what it leaves
alone.

Only pinned items change. Running apps, minimized windows and every Dock setting the
profile does not claim stay exactly as they are.

### Auto-save

The profile you last activated tracks the Dock: drag an app in or out and the profile is
updated to match. Turn it off in Settings → Active profile.

## The wallpaper

A profile can carry a wallpaper, set when the profile is activated. `NSWorkspace` sets
the picture for whichever Space is on screen at that moment, so the wallpaper lands on
the desktop you are on — which is how "the development desktop" ends up looking
different from the others. Optionally on every display, or just the main one.

Switching Spaces is not part of a profile. macOS has no public API for it, so it would
mean posting `Control + ←/→` keystrokes and asking for Accessibility access — a
permission for something the Dock profile itself never needed.

## Permissions

Dock Profiler asks for **no privacy permissions at all**. It reads and writes
`com.apple.dock`, sets the desktop picture through `NSWorkspace`, and registers its
shortcut through Carbon hot keys — none of which need Accessibility, Screen Recording or
Automation access.

| Permission | Needed for | Prompted |
| --- | --- | --- |
| *(none)* | Dock profiles, wallpaper | Nothing to grant |
| *(none)* | The global shortcut | Carbon hot keys need no permission |
| Login item | Launch at login | Settings toggle (`SMAppService`) |

## Layout

```
Sources/DockProfiler/
  DockProfilerApp.swift          MenuBarExtra + Settings scenes, app delegate
  Models/DockTile.swift      One Dock item; keeps the Dock's own tile dictionary verbatim
  Models/DockProfile.swift   Profile, appearance and wallpaper options
  Services/DockService.swift Reads/writes com.apple.dock, restarts the Dock
  Services/WallpaperService.swift  Sets the desktop picture
  Services/ProfileStore.swift  Profiles, activation, JSON persistence
  Services/DockWatcher.swift   Notices Dock changes for auto-save
  Services/AppSettings.swift   Preferences + login item
  Services/HotKeyManager.swift Carbon global shortcut
  Services/KeyCombo.swift      A recorded shortcut, in Carbon's terms
  UI/                        Menu bar panel, quick switcher, welcome, manager window, editor, settings
```

Profiles live in `~/Library/Application Support/Dock Profiler/profiles.json`. Each item keeps
the Dock's original tile dictionary (bookmark data, labels, `dock-extra`, …) so a
captured Dock is restored exactly, not approximated.

## Not included

**Focus mode integration.** macOS exposes no supported way to observe the active Focus,
so profiles are switched by hand, by the menu bar, or by whatever you script around them.

What changed per version is in the [changelog](./CHANGELOG.md).

## Releasing

`.github/workflows/release.yml` builds, signs, notarizes and staples on a `macos-15`
runner, then attaches a zip and a disk image to the release.

1. Add an entry to `CHANGELOG.md`, under a new `## [<version>] - <date>` heading.
2. Bump the version with `npm version patch` (or `minor` / `major`). This updates
   `package.json` — the only place the version lives — and commits and tags it as
   `v<version>`, npm's default tag format.
3. `git push --follow-tags`.
4. Publish a GitHub release for that tag.

The tag and `package.json` have to agree, or the workflow stops before building — that
guard is what makes `npm version` the source of truth rather than an editor typo.

The workflow also runs from *Actions → Release → Run workflow*, where a `tag` input
attaches the build to an existing release — useful when a release's build failed and you
would rather repair it than cut a new one.

These repository secrets are needed for a signed build:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application certificate, exported as `.p12` and base64-encoded |
| `APPLE_ID` | The Apple ID used for notarization |
| `APPLE_TEAM_ID` | Your team identifier |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID |
| `HOMEBREW_TAP_TOKEN` | A token with write access to `estruyf/homebrew-tap`, for the step below |

Without `MACOS_CERTIFICATE` the run still finishes, producing an unsigned build — enough
to check that a tag compiles, not enough to hand to anyone. Nothing unsigned is ever
attached to the release or pushed to the tap; the workflow warns and stops at those
steps instead.

## The Homebrew tap

A published, non-prerelease, signed release also updates `estruyf/homebrew-tap`, so
`brew install --cask estruyf/tap/dock-profiler` resolves to it. `homebrew/dock-profiler.rb`
in this repo is the source of truth — everything in it except `version` and `sha256` is
edited here by hand, and `homebrew/publish-cask.sh` stamps those two fields and pushes
the result to the tap. Run it yourself with `HOMEBREW_TAP_TOKEN` unset to fall back to
your own `git`/`gh` credentials:

```sh
./homebrew/publish-cask.sh          # stamp the cask and print it
./homebrew/publish-cask.sh --push   # also push it to the tap
```

## Screenshots

`./Scripts/make_screenshots.sh` regenerates everything in `docs/screenshots` from the
real views, using demo profiles written to a throwaway store. Your own profiles are
never read or touched.

## Restoring your Dock

Dock Profiler never deletes anything, but if you want to go back to a known state:

```sh
defaults import com.apple.dock path/to/com.apple.dock.plist && killall Dock
```
