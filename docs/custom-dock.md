# The custom dock

A profile can carry a dock that Dock Profiler draws itself, so live things — a clock,
what is playing, your battery, your AI allowances, the agents working in your editors —
can sit next to your apps. The macOS Dock has no extension point for that, so this is a
separate floating panel. It never takes focus, follows you across Spaces, and stays out
of the way of the real Dock. (Why it is built that way is in
[How it works](./how-it-works.md#the-custom-docks-window).)

![The custom dock: apps, then clock, date, battery, Trash and a Downloads stack](./screenshots/custom-dock.png)

Turn it on in the profile editor's **Custom Dock** tab. The dock follows the active
profile: activate one with a custom dock and it appears, activate one without and it
goes away, edit the active profile and it updates as you go.

## Two forms

- **Apps and widgets** — one dock holding the profile's apps and its widgets, in the
  order you arrange them in the editor's preview, standing in for the macOS Dock. App
  tiles launch or bring an app forward, carry the running dot, and offer Hide, Quit and
  Show in Finder on right-click. Optionally, apps that are open but not in the profile
  follow after a divider, as the Dock does. While such a profile is active the macOS
  Dock is parked out of the way (⌘⌥D still toggles it); it comes back with the next
  profile that does not stand in for it, and when Dock Profiler quits.
- **Widgets only** — a strip of widgets beside the macOS Dock, which keeps doing its
  job.

## Position

Either form goes on any edge: bottom or top, hugging the left, centre or right; or left
or right, centred on the edge and stacked as a column with the dots beside the icons.
In a column every widget becomes a tile the size of an icon and re-flows to fit — the
battery's percentage moves under its icon, each agent session becomes a dot over its
folder name — and hovering any tile shows the dock's own tooltip with the detail.

<img src="./screenshots/custom-dock-column.png" alt="The same dock as a column on the left edge" width="188">

**Displays** puts the dock on the main display alone or on every display, each with a
dock of its own. Any display can be given an edge and alignment of its own on its row
underneath, so two displays side by side can keep their docks on the outer edges and
leave the edge between them clear for the pointer.

**Hide until the pointer reaches its edge** slides it off screen and brings it back
when the pointer runs into the edge where it lives. While it is away, a slim mark stays
on the edge where it went, so you know something is there to open; it brightens a
little as the pointer heads its way. Turn that off if you would rather have the edge to
yourself.

## Look

- A **size** slider (36–96 pt) scales icons, cards and type together.
- **Magnification** grows the tiles under the pointer, pushing their neighbours aside,
  as the Dock does.
- A **look** picks the slab: following the system, as the Dock does; light or dark
  whatever the system appearance — tiles, tips and stacks follow the slab; on macOS
  Tahoe, **Liquid Glass**, refracting what is behind it; or **transparent**, no slab at
  all, each widget on its own card. Those two read the wallpaper under the dock and go
  light or dark to suit it, as the Tahoe Dock does.
- The slab can blur what is behind it or be drawn solid — clear, for Liquid Glass —
  and is solid regardless while macOS's Reduce transparency is on.
- It can take a wash of the profile's colour, so each profile's dock is its own.
- Widgets can lose their cards for a flatter look.
- A **density** picks how tightly the tiles are packed, the corners squaring off as it
  tightens.

## Rearranging

Arrange apps and widgets in the editor's preview, or in place, the Dock's way: hold a
tile or widget for a moment, drag it along the dock and let go — the profile is updated
as you drop. Widgets keep their place next to the app they follow, so auto-save
rearranging the app list underneath does not scatter them.

Right-click anywhere on the dock for **Custom Dock Settings…**, which opens the profile
on this tab.

## Widgets

- **Clock**, **Date**, **Battery** — the glanceable ones.
- **Now Playing** — the track in Music or Spotify, with its album art. Click to play
  or pause; skip from the context menu, or turn on previous/next buttons on its card.
- **Profiles** — the active profile; click for the list and switch without going to
  the menu bar.
- **Trash** — full or empty. Click to open it, drop files on it to delete them, empty
  it from the context menu. Handy in a combined dock, which stands in for the Dock's own.
- **AirDrop** — drop files on it and the AirDrop picker opens with them, so sending
  something to the phone is one drag. Click it for Finder's AirDrop window.
- **Folder** — a folder that opens into its most recent files, newest first, like a
  Dock stack. Downloads by default; choose any folder on its card in the editor.
- **App Stack** — several apps folded into one tile, a grid of their icons, that opens
  into the apps. Add apps on its card or drop them from Finder.
- **Agents** — see below. It can also fold into one tile with a count that opens into
  the list.
- **AI Usage** — what is left of your Claude and GitHub Copilot allowances, a card per
  service, as numbers, rings or bars. See below.

Stacks open in a panel beside the dock, on the side away from its edge, that goes away
on a click anywhere else — and, like the dock, never takes focus from the front app.

### Agents

If you use [Agent Frame](https://github.com/estruyf/vscode-agent-frame) in VS Code, the
**Agents** widget shows a card per Claude Code session — folder, and whether it is
working, waiting for you, or idle, in Agent Frame's own colours, the ones that need you
first. There is nothing extra to set up. Beyond four sessions the rest fold into a menu.

Click a card to bring that session's editor forward — VS Code, Insiders or Cursor,
whichever is hosting it.

### AI Usage

The **AI Usage** widget shows how much of your **Claude** and **GitHub Copilot**
allowances is left — one card per service, drawn as numbers, rings or bars (pick on its
card in the editor, along with which services to track). Each card shows the tightest
of the service's main windows: Claude's 5-hour and weekly limits, Copilot's premium
requests for the month. Blue while there is plenty, orange under a quarter, red under a
tenth. Click a card for every window with its reset time and countdown — Claude's
per-model weekly limits included — and refresh or jump to the service's usage page from
the context menu.

There is nothing to sign in to: the widget reads the sign-in Claude Code and the
Copilot editor extensions already leave on your Mac. What it reads, and the one
Keychain prompt you will see, are in [Permissions](./permissions.md#the-ai-usage-widget).
