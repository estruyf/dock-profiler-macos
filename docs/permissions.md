# Permissions and privacy

Everything Dock Profiler does is local. There is no account, no sync, no analytics.
The only network requests are made by two widgets you opt into: the AI Usage widget
asks the services you track for your allowance, and Now Playing fetches Spotify album
art from the URL Spotify hands it.

Dock Profiler asks for **no privacy permissions** for what it does itself. It reads and
writes `com.apple.dock`, sets the desktop picture through `NSWorkspace`, and registers
its shortcut through Carbon hot keys — none of which need Accessibility, Screen
Recording or Automation access. A few widgets talk to other apps or read protected
folders, and macOS asks about those the first time they do. The one exception is
notification badges on a combined dock's app tiles, which are read from the macOS Dock
through Accessibility — an option that is off until you switch it on.

| Permission | Needed for | Prompted |
| --- | --- | --- |
| *(none)* | Dock profiles, wallpaper, most widgets | Nothing to grant |
| *(none)* | The global shortcut | Carbon hot keys need no permission |
| Automation → Music / Spotify | Now Playing's first read and its play, pause and skip; track changes themselves arrive over notifications that need nothing | Once, when the widget first asks the player |
| Automation → Finder | Empty Trash from the Trash widget | Once, the first time you empty it |
| Files and Folders | The Trash widget counting what is in the Trash; the Folder widget reading a protected folder such as Downloads | Once per folder |
| Keychain | The AI Usage widget reading Claude Code's token from the `Claude Code-credentials` item | Once per build, with Always Allow |
| Bluetooth | The Accessories widget reading the charge of accessories from other makers — a Logitech mouse, headphones — over the Bluetooth battery service. Apple's accessories need nothing | Once, when an Accessories widget first appears |
| Accessibility | Notification badges on a combined dock's app tiles, read from the macOS Dock's own tiles | When **Show notification badges on app tiles** is switched on; macOS shows its dialog once, after that it is granted under Privacy & Security → Accessibility |
| Login item | Launch at login | Settings toggle (`SMAppService`) |

## The AI Usage widget

There is nothing to sign in to: the widget reads the sign-in each service's own tools
leave on your Mac, and sends that token only to that service's own usage endpoint.

- **Claude** — reading the Keychain item brings up macOS's Keychain dialog the first
  time; **Always Allow** settles it for that build of the app. The token is only read,
  never refreshed. If it has expired, the card says so; run `claude` once and the card
  picks up the new sign-in by itself within half a minute.
- **Copilot** — sign in to Copilot in VS Code or Xcode and the card fills in. Nothing
  else to do.

Where each widget gets its data is spelled out in [How it works](./how-it-works.md).
