# Building, releasing and publishing

Everything a contributor or maintainer needs. Users can stop at the
[README](../README.md).

## Requirements

- macOS 14 or later to run the app.
- A Swift 6 toolchain (Xcode 16) to build it.
- `npm` for the convenience scripts below — nothing is installed from npm; the
  scripts only wrap `./Scripts/build_app.sh`.

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
| `build` | Universal build (`arm64` + `x86_64`) |
| `build:install` | Universal build, copied to /Applications and launched |
| `build:zip` / `build:dmg` | Universal build, also zipped / made into a disk image |
| `sign` | Zipped, signed with the Developer ID `CODESIGN_IDENTITY` finds |
| `notarize` | Signed, notarized and stapled — needs a stored `xcrun notarytool` profile |
| `release` | `notarize`, plus a disk image — what CI runs |
| `open` / `quit` | Launch / quit the built app |
| `screenshots` | Regenerate `docs/screenshots` (see below) |
| `icon` | Regenerate the app icon set from `Scripts/make-icon.swift` |
| `cask` | Stamp the Homebrew cask (see below) |
| `clean` | Remove `.build` and `build` |

`./Scripts/build_app.sh` on its own produces a universal build in `build/`, signed
with the Apple Development certificate in your keychain if there is one, ad-hoc
otherwise. The difference matters for the permissions: macOS ties an Accessibility
grant to the app's signature, and an ad-hoc signature is a hash of the binary that
changes with every build — so after a rebuild the badges and window lists stop
working while System Settings still shows Dock Profiler as allowed. A certificate
keeps the grant. If you have been on ad-hoc builds and the grant has gone stale,
reset it once and allow the app again:

```sh
tccutil reset Accessibility dev.eliostruyf.DockProfiler
```

See the header of the script for signing and notarization details.

The app is a menu bar item (`LSUIElement`), so it has no Dock icon. The profile manager
opens from the menu bar, or by opening the app again from Finder.

macOS only knows about the `dockprofiler://` URL scheme once it has registered the
bundle. Launching the app once is normally enough; if not,
`lsregister -f "build/Dock Profiler.app"` forces it.

## Source layout

```
Sources/DockProfiler/
  DockProfilerApp.swift          MenuBarExtra + Settings scenes, app delegate
  Models/DockTile.swift      One Dock item; keeps the Dock's own tile dictionary verbatim
  Models/DockProfile.swift   Profile, appearance and wallpaper options
  Models/CustomDock.swift    Widget kinds, the custom dock's options, and the mixed row
  Services/DockService.swift Reads/writes com.apple.dock, restarts the Dock
  Services/WallpaperService.swift  Sets the desktop picture
  Services/BatteryMonitor.swift    IOKit power source, for the battery widget
  Services/AgentSessionMonitor.swift  Agent Frame's session files, for the agents widget
  Services/NowPlayingMonitor.swift    Music and Spotify, for the now-playing widget
  Services/TrashMonitor.swift         ~/.Trash, for the trash widget
  Services/AIUsageMonitor.swift       Claude and Copilot allowances, for the AI usage widget
  Services/AppleScriptRunner.swift    AppleScript in an osascript child, off the main thread
  Services/RunningAppsMonitor.swift   Running apps, for the custom dock's dots
  Services/DockBadgeMonitor.swift     The Dock's badges through Accessibility, for the tiles
  Services/ProfileStore.swift  Profiles, activation, JSON persistence
  Services/ProfileExchange.swift  .dockprofile export and import, made portable across Macs
  Services/DisplayIdentity.swift  Telling displays apart, for per-display dock positions
  Services/DockWatcher.swift   Notices Dock changes for auto-save
  Services/AppSettings.swift   Preferences + login item
  Services/HotKeyManager.swift Carbon global shortcut
  Services/KeyCombo.swift      A recorded shortcut, in Carbon's terms
  UI/                        Menu bar panel, quick switcher, welcome, manager window, editor, settings
  UI/CustomDockWindowController.swift  The floating custom dock, following the active profile
  UI/DockTooltip.swift                 The dock's own hover tips
  UI/DockStack.swift                   The panel a stack widget opens into
  UI/DockWidgets.swift                 Now playing, profiles, trash, folder and app stacks, AI usage
```

Profiles live in `~/Library/Application Support/Dock Profiler/profiles.json`. Each item
keeps the Dock's original tile dictionary (bookmark data, labels, `dock-extra`, …) so a
captured Dock is restored exactly, not approximated. More on that in
[How it works](./how-it-works.md).

## Screenshots

`./Scripts/make_screenshots.sh` (or `npm run screenshots`) regenerates everything in
`docs/screenshots` from the real views, using demo profiles written to a throwaway
store. Your own profiles are never read or touched.

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
