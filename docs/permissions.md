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
Accessibility, which two things on a combined dock's app tiles need: notification
badges, read from the macOS Dock — an option that is off until you switch it on — and
the list of an app's open windows in a tile's right-click menu, which is simply empty
until access is granted.

| Permission | Needed for | Prompted |
| --- | --- | --- |
| *(none)* | Dock profiles, wallpaper, most widgets | Nothing to grant |
| *(none)* | The global shortcut | Carbon hot keys need no permission |
| Automation → Music / Spotify | Now Playing's first read and its play, pause and skip; track changes themselves arrive over notifications that need nothing | Once, when the widget first asks the player |
| Automation → Finder | Empty Trash from the Trash widget | Once, the first time you empty it |
| Files and Folders | The Trash widget counting what is in the Trash; the Folder widget reading a protected folder such as Downloads | Once per folder |
| Keychain | The AI Usage widget reading Claude Code's token from the `Claude Code-credentials` item | Only when you ask the card to refresh; a refresh on the timer never brings the dialog up |
| Bluetooth | The Accessories widget reading the charge of accessories from other makers — a Logitech mouse, headphones — over the Bluetooth battery service. Apple's accessories need nothing | Once, when an Accessories widget first appears |
| Accessibility | Notification badges on a combined dock's app tiles, read from the macOS Dock's own tiles; the open windows of an app in its tile's menu, read from the app itself | When **Show notification badges on app tiles** is switched on, or from **Show Windows Here…** in a tile's menu, or from the welcome screen; macOS shows its dialog once, after that it is granted under Privacy & Security → Accessibility |
| Login item | Launch at login | The toggle on the welcome screen or in Settings (`SMAppService`) |
| *(none)* | The Agents widget finding the sessions running on this Mac | The kernel answers for your own processes; nothing to grant |

## The Agents widget

The widget finds the Claude Code and Codex sessions running on this Mac by their own
processes. Everything it reads is *metadata*, and only about processes running as you:

- which processes are running (`proc_listallpids`), what each was started as
  (`KERN_PROCARGS2` — the command line, which is where the session id comes from), the
  folder each is in (`proc_pidinfo`), and its parent, so a session is not counted twice;
- when the agent last wrote to its record of that folder — the modification time of the
  newest file in `~/.claude/projects/<folder>`, found by listing the directory.

No transcript is ever opened. Nothing of a conversation, a prompt or generated code is
read, and nothing is sent anywhere: the widget makes no network requests at all. This is
also why a session found this way is only ever **working** or **idle** — whether an
agent is waiting for an answer is not something anything outside it says. Agent Frame's
hooks are what report waiting; see [The custom dock](./custom-dock.md#agents).

Turn the whole process side off with **Find the sessions running on this Mac** on the
widget's card.

## The AI Usage widget

There is nothing to sign in to: the widget reads the sign-in each service's own tools
leave on your Mac, and sends that token only to that service's own usage endpoint.

- **Claude** — reading the Keychain item brings up macOS's Keychain dialog, and
  **Always Allow** settles it until Claude Code rotates its token: rewriting the item
  drops the app from the item's access list, and the next read would ask again. So the
  widget asks as little as it can. The token is kept until it expires, which leaves the
  Keychain alone between rotations, and a refresh on the timer reads without the dialog:
  when macOS would ask, the card says **Keychain access needed**, keeps the last numbers
  on screen, and brings the dialog up only when you click that line or **Refresh**. The
  token is only read, never refreshed. If it has expired, the card says so; run `claude`
  once and the card picks up the new sign-in by itself within half a minute.
- **Copilot** — sign in to the GitHub CLI (`gh auth login`), or to Copilot for Xcode,
  and the card fills in. VS Code's own Copilot sign-in is kept where other apps cannot
  read it, so on a Mac with only VS Code, `gh` is the way in.

Where each widget gets its data is spelled out in [How it works](./how-it-works.md).
