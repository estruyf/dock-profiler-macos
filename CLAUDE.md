# Dock Profiler

A macOS menu bar app (`LSUIElement`, no Dock icon) for Dock profiles, each with an
optional desktop (Space + wallpaper), plus a floating custom dock with widgets.
Swift 6 toolchain, Swift 5 language mode, SwiftPM only (no Xcode project), macOS 14+.
Bundle id: `dev.eliostruyf.DockProfiler`. Repo: `estruyf/dock-profiler-macos`.

## Where things are

- `Sources/DockProfiler/` — `Models/`, `Services/`, `UI/`. The file-by-file map is in
  [docs/development.md](docs/development.md#source-layout); keep it up to date when you
  add a service or a major UI file.
- `Scripts/build_app.sh` — the only build script; every `npm run` script wraps it.
- `Resources/Info.plist` — `__VERSION__` / `__BUILD__` are filled in at build time.
- `homebrew/` — the cask (source of truth for the tap) and `publish-cask.sh`.
- `.github/workflows/release.yml` — builds, signs, notarizes and publishes a release.
- `docs/` — user docs (`custom-dock.md`, `permissions.md`, `automation.md`,
  `how-it-works.md`) and maintainer docs (`development.md`).

## Working on the code

- Build to check your work: `npm run build:debug` (current arch, fast). Launch with
  `npm run quit && npm run open`. There is no test target; a clean build plus running
  the app is the check.
- `npm` installs nothing — `package.json` only holds scripts and the **version**, which
  lives nowhere else. Never hard-code a version in Swift or the plist.
- Match the surrounding style: comments explain *why* (the macOS quirk, the trade-off),
  in full sentences. Keep that density; don't add comments that restate the code.
- Profiles and stores must stay readable across versions. When a setting changes shape,
  keep reading (and writing) the old key, as `DockVisibility` does for `autohide`.
- Privacy is a feature here: read metadata, not content (e.g. agent sessions read
  process info and file mtimes, never transcripts). Say what is read in
  `docs/permissions.md` when you add anything that touches another app's data.
- The AI Usage widget covers Claude and Copilot only, on purpose: the app never asks
  for API keys.
- A user-visible change updates the docs in the same commit: `README.md` and/or the
  relevant page in `docs/`, and an entry in `CHANGELOG.md` (see below).

## Commits

- Commit only when asked. Work on `main` unless told otherwise (this is a solo repo).
- Subject: a plain-language summary of what the user gets, not a conventional-commit
  prefix (e.g. "Keep an app pinned on the custom dock when it is quit").
- Body: the developer's view — what changed, the APIs involved, why it's done that way.

## CHANGELOG.md

Keep a Changelog format, semantic versioning. Entries are written **for users**, not
developers: a bold one-line lead (`- **Dividers.** …`), then what it does and where to
find it in the UI (*Position → Showing*). For fixes, describe the symptom the user saw,
then briefly why and what changed. No type names or APIs — those go in the commit body.

New entries go under `## [Unreleased]` (keep that heading at the top, even when empty),
grouped as `### Added`, `### Changed`, `### Fixed`, `### Removed`.

## Publishing a new release

When asked to "publish a release" / "cut a release" / "ship it", do the following.
The user asking is the go-ahead; still stop and ask if anything below looks off.

1. **Preflight.**
   - `git status` is clean apart from untracked local files (`.claude/`, `.vscode/`), and
     the branch is `main`.
   - `git pull --ff-only` so you are not behind `origin/main`.
   - `npm run build` succeeds (universal build). Fix or report failures; don't release
     a broken build.
   - There is something to release: `git log $(git describe --tags --abbrev=0)..HEAD`
     is non-empty.

2. **Pick the version.** From the changes since the last tag:
   - `patch` — only fixes.
   - `minor` — anything under *Added* or a user-visible *Changed*.
   - `major` — only if the user says so.
   Tell the user which bump you chose and why, in one line, and carry on.

3. **Write the changelog.**
   - If `## [Unreleased]` has entries, rename that section to
     `## [<version>] - <YYYY-MM-DD>` (today) and put a fresh empty `## [Unreleased]`
     above it.
   - If it is empty but there are unreleased commits, write the entries from those
     commits (in the user-facing voice above) and show them to the user before going on.
   - Commit it: `git commit -am "Changelog for <version>"`, unless the changelog was
     already committed with the feature commit.

4. **Bump and tag.** `npm version <patch|minor|major>`. This edits `package.json`,
   commits it with the bare version as the message (`1.14.0`) and creates the annotated
   tag `v1.14.0`. Don't edit `package.json` by hand and don't create the tag yourself —
   the workflow refuses to build when the tag and `package.json` disagree.

5. **Push.** `git push --follow-tags`.

6. **Create the GitHub release.** Title is the bare version, notes are that version's
   CHANGELOG section *without* its `## [x.y.z]` heading:

   ```sh
   VERSION=$(node -p "require('./package.json').version")
   awk -v v="$VERSION" '
     $0 ~ "^## \\[" v "\\]" {on=1; next}
     on && /^## \[/ {exit}
     on {print}
   ' CHANGELOG.md > "$TMPDIR/notes.md"
   gh release create "v$VERSION" --title "$VERSION" --notes-file "$TMPDIR/notes.md"
   ```

   Not a draft and not a prerelease unless the user asks (a prerelease skips the
   Homebrew tap).

7. **Follow the workflow.** Publishing triggers `.github/workflows/release.yml`, which
   builds, signs, notarizes and staples on CI, attaches
   `DockProfiler-<version>-macos-universal.{zip,dmg}` to the release, and updates the
   Homebrew tap (`estruyf/homebrew-tap`). Watch it:

   ```sh
   gh run list --workflow release.yml --limit 1
   gh run watch <run-id> --exit-status
   ```

   Notarization takes a few minutes. When it's done, confirm with
   `gh release view v<version>` that both assets are attached.

8. **Report back:** the version, the release URL, whether the assets are attached and
   whether the tap step pushed (or was skipped, with the warning it printed).

### If something goes wrong

- **Version check failed in CI** — the tag and `package.json` disagree. Don't retag
  silently; tell the user.
- **Build/notarization failed** — fix on `main`, then re-run *Actions → Release → Run
  workflow* with `tag: v<version>` to attach a fresh build to the existing release
  (`gh workflow run release.yml -f tag=v<version>`). No need to cut a new version
  unless the fix changes the code that ships.
- **Tap not updated** (e.g. `HOMEBREW_TAP_TOKEN` missing) — `./homebrew/publish-cask.sh
  --push` locally, which uses the user's own `git`/`gh` credentials.
- Never delete a published release or a pushed tag without asking.

Full background (secrets, signing, notarization) is in
[docs/development.md](docs/development.md#releasing).
