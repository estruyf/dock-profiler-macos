# How it works

What Dock Profiler actually touches when you activate a profile, where it keeps its
data, and why some things are built the way they are. Nothing here is needed to use the
app — the [README](../README.md) covers that.

## What activation writes

A profile is a set of parts, each of which can be switched on or off. Activating it
applies the parts that are on and leaves everything else alone.

| Part | What happens on activation |
| --- | --- |
| Pinned apps and spacers | Replaces `persistent-apps` in `com.apple.dock` |
| Folders, files, stacks *(optional)* | Replaces `persistent-others` — off by default, so that side of the Dock is left alone |
| Dock appearance *(optional)* | Position, size, magnification, auto-hide, recents, minimize-into-icon |
| Desktop wallpaper *(optional)* | Sets the desktop picture on the desktop you are on |
| Custom dock *(optional)* | Shows Dock Profiler's own dock — see [the custom dock](./custom-dock.md) |

After writing `com.apple.dock` the Dock process is restarted so it picks the change up.
Only pinned items change: running apps, minimized windows and every Dock setting the
profile does not claim stay exactly as they are.

Spacers come in two sizes, regular and small. Flexible spacers are not offered — macOS
does not apply them reliably — though one already in a captured Dock is preserved as-is.

## Where profiles live

`~/Library/Application Support/Dock Profiler/profiles.json`.

Each item keeps the Dock's original tile dictionary (bookmark data, labels,
`dock-extra`, …) verbatim, so a captured Dock is restored exactly, not approximated.
Settings are ordinary `UserDefaults`.

## Auto-save

The profile you last activated tracks the Dock: a watcher notices changes to
`com.apple.dock` and, when the pinned items differ from the active profile, updates the
profile to match. Turn it off in Settings → Active profile.

Widgets in a custom dock keep their place among the apps by anchoring to the app before
them rather than to a position, so when auto-save replaces the app list wholesale each
widget stays next to the app it followed.

## The wallpaper

`NSWorkspace` sets the desktop picture for whichever Space is on screen at that
moment, so the wallpaper lands on the desktop you are on — which is how "the
development desktop" ends up looking different from the others. Optionally on every
display, or just the main one.

Switching Spaces is not part of a profile. macOS has no public API for it, so it would
mean posting `Control + ←/→` keystrokes and asking for Accessibility access — a
permission for something the Dock profile itself never needed.

## The global shortcut

The quick switcher's shortcut is registered through Carbon's `RegisterEventHotKey`, so
it needs no Accessibility access. If another app already owns the combination, Settings
says so.

## The custom dock's window

The macOS Dock has no extension point: `persistent-apps` only takes apps, folders,
links and spacers, so nothing live can be pinned to it. The custom dock is a borderless
panel Dock Profiler draws itself. It never takes focus, follows you across Spaces, and
sits below the Dock's own window level so an auto-hidden macOS Dock still slides in
over it.

While a combined dock (apps and widgets) is active the macOS Dock is parked —
auto-hidden with a delay so long it never comes back on hover (⌘⌥D still toggles it).
Its own settings come back with the next profile that neither stands in for it nor
manages Dock settings itself, and when Dock Profiler quits.

In Mission Control a combined dock stays on screen in place of the macOS Dock — drawn
just above the Dock's own window level, the one Mission Control does not hide. Mission
Control still draws the parked macOS Dock underneath; there is no API to stop it, but
the custom dock sits in front of it.

**Hide until the pointer reaches its edge** polls the pointer position rather than
installing an event tap, so it needs no Accessibility permission either.

Per-display positions are stored by the display's own id, so a display keeps its place
when it is unplugged and plugged back in; a display plugged in later takes the shared
position until it is given one.

## Where the widgets get their data

| Widget | Source |
| --- | --- |
| Battery | IOKit power sources |
| Now Playing | Distributed notifications from Music and Spotify for track changes; AppleScript (in an `osascript` child, off the main thread) for the first read and for play, pause and skip |
| Trash | `~/.Trash`, watched for changes; AppleScript to Finder for Empty Trash |
| Folder | The folder's contents, newest first |
| Agents | The session files [Agent Frame](https://github.com/estruyf/vscode-agent-frame)'s hooks keep in `~/.agent-frame/sessions`. The hook records the agent's process; walking up from it reaches the app hosting the session — VS Code, Insiders, Cursor — so the folder is opened with that app |
| AI Usage — Claude | Claude Code's OAuth token from the `Claude Code-credentials` Keychain items (newest first, the first with a live token wins) or `~/.claude/.credentials.json`, sent to Anthropic's OAuth usage endpoint. The token is only read, never refreshed — refreshing it from outside would sign Claude Code out |
| AI Usage — Copilot | The GitHub token the Copilot extensions for VS Code and Xcode keep in `~/.config/github-copilot/apps.json`, sent to the same endpoint those editors ask (`copilot_internal/user`) |

The AI Usage numbers refresh every five minutes while the widget is on screen, and when
the Mac wakes.

## The `.dockprofile` format

An exported profile is JSON. To make it travel between Macs:

- paths under your home folder go out as `~/…` and land in the other user's home;
- the Dock's own per-Mac bookmark data is left out;
- an app that lives somewhere else on the other Mac is found by its bundle identifier;
- a wallpaper that is not there is switched off with its path kept, so it is plain what
  was meant;
- imported profiles get fresh ids and a name no other profile has, so a file can be
  imported twice;
- apps that are not installed at all stay in the profile, marked as missing, until
  they are.

## Not included

**Focus mode integration.** macOS exposes no supported way to observe the active Focus,
so profiles are switched by hand, by the menu bar, or by whatever you script around
them — see [Automation](./automation.md).

## Restoring your Dock

Dock Profiler never deletes anything, but if you want to go back to a known state:

```sh
defaults import com.apple.dock path/to/com.apple.dock.plist && killall Dock
```
