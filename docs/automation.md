# Automation

Dock Profiler registers a `dockprofiler://` URL scheme, so anything that can open a URL
can drive it — Raycast, Alfred, Shortcuts, Keyboard Maestro, a shell alias, a cron job.

```sh
open "dockprofiler://switch"                    # toggle the quick switcher
open "dockprofiler://profiles"                  # open the profile manager
open "dockprofiler://welcome"                   # show the welcome screen again
open "dockprofiler://activate?name=Development" # activate a profile by name
open "dockprofiler://activate?id=<uuid>"        # …or by id
```

Profile ids are in `~/Library/Application Support/Dock Profiler/profiles.json`, or in
an exported `.dockprofile` file. Names are matched exactly.

## Examples

**Raycast / Alfred** — create a script command or workflow that runs
`open "dockprofiler://activate?name=Writing"` and give it a hotkey or keyword.

**Shortcuts** — an *Open URLs* action with `dockprofiler://activate?name=Meetings`,
which can then be triggered from a Focus automation, a time of day, or Siri.

**Shell** — a couple of aliases:

```sh
alias work='open "dockprofiler://activate?name=Work"'
alias play='open "dockprofiler://activate?name=Home"'
```

## Keyboard

The quick switcher's global shortcut (**⌥⌘D** by default) works everywhere, without
any permission. Change or clear it in Settings → Quick switcher. Inside the switcher:
type to filter, `↑`/`↓` or `⇥` to move, `↵` to activate, `⌘1`–`⌘9` to jump straight to
a profile, `esc` to close.

## If the scheme does nothing

macOS only knows about the scheme once it has registered the app bundle. Launching Dock
Profiler once is normally enough. If you built it yourself and `open` still cannot find
it, see [Building](./development.md#build--run).
