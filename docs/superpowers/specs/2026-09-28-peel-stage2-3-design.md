# peel Stages 2–3 — Design Spec

**Date:** 2026-09-28
**Status:** Draft for review
**Builds on:** `2026-09-28-peel-design.md` (Stage 1: ConvertKit + `peel` CLI, merged to `master`)

## 1. Purpose

Give peel the drag-and-drop / right-click convenience of the paid app it replaces, on top of the
Stage 1 engine:

- **Stage 2 — Finder Quick Actions:** right-click files in Finder → *peel: Convert To…*,
  *peel: Merge PDFs*, *peel: Split PDF*, *peel: Extract Here*, *peel: Zip*.
- **Stage 3 — peel.app:** a small native window + menu-bar popover. Drop files, pick an action,
  set options, see results.
- **Missing optional tools handled everywhere:** when ffmpeg / cwebp / avifenc / unar /
  rsvg-convert (or Homebrew itself) is missing, every surface says what's missing and how to
  install it, and never fails silently or cryptically.

### What the user said
- "Do Stage 2 and Stage 3, go for me" — design decisions are delegated.
- Install unar and librsvg on this Mac (done).
- "Make sure that if features aren't available because someone doesn't have dependencies
  installed, that is properly handled."
- Earlier: installable and runnable by someone else; no App Store / Homebrew distribution needed.

### Assumptions
- Same platform as Stage 1: macOS 13+, Swift toolchain only (no Xcode required to build).
- Personal-use polish level: a default app icon is fine; no signing beyond ad-hoc; no sandbox.

### Success criteria
1. `./install.sh` installs the CLI, the Quick Actions and `~/Applications/peel.app`.
2. Each Quick Action works from Finder on files with spaces/accents, and reports results with a
   notification and failures with a dialog.
3. peel.app: drop files (window, menu-bar popover, or Dock icon) → valid actions for that
   selection are offered → running one produces the same outputs, naming and safety guarantees
   as the CLI (never overwrite inputs, numbered collisions, atomic writes).
4. With a tool missing, the CLI, Quick Actions and app each show the specific tool, what it
   unlocks, and the `brew install …` command; the app disables the affected actions with that
   reason and offers to copy the command. If Homebrew itself is missing, point to https://brew.sh.
5. All logic outside SwiftUI views and osascript glue is unit-tested; the Quick Action workflows
   are exercised end-to-end headless with `automator -i`.

### Non-goals
- App Store, notarization, auto-update, sandboxing, a custom icon.
- Drag-and-drop *onto the menu-bar icon itself* (the popover is clicked open, then files are
  dropped into it — standard `MenuBarExtra` behaviour).
- In-app page-thumbnail editing (visual reorder). Reorder stays CLI-only.
- Installing Homebrew tools on the user's behalf from the app.

## 2. Architecture

```
ConvertKit (existing)
 └─ Actions/                    NEW — shared by Quick Actions and the app
     ├─ PeelAction.swift        what can be done (enum + options)
     ├─ ActionCatalog.swift     which actions fit a selection, and whether each is available
     └─ ActionRunner.swift      runs an action → [ActionOutcome], with cancellation
PeelCLI (existing)
 ├─ QuickActionCommands.swift  NEW — `peel install-quick-actions`, `uninstall-quick-actions`,
 │                              hidden `peel quick-action <name> <files…>`
 └─ QuickActions/               NEW — workflow generator + UI glue (osascript)
PeelAppCore                     NEW library — UI-free app model (ObservableObject), testable
PeelApp                         NEW executable — SwiftUI views, window + MenuBarExtra
scripts/build-app.sh            NEW — assembles peel.app bundle, ad-hoc signs, installs
```

Principles carried over: engine/UI separation, one capability registry, safe outputs, local only.
The CLI's existing commands stay as they are (their tests pin behaviour); the new Actions layer
reuses the same backends, planner and naming suffixes (`-merged`, `-p1-3`, `-rotated`, …).

## 3. Shared Actions layer (ConvertKit)

### 3.1 `PeelAction`
```
convert(to: FileFormat, options: ConvertOptions)
pdfMerge
pdfSplit(ranges: PageRange?)
pdfExtract(pages: PageRange)
pdfDelete(pages: PageRange)
pdfRotate(degrees: Int, pages: PageRange?)
pdfText
mediaCompress(targetBytes: Int?)
mediaTrim(from: Double, until: Double)
mediaGif(fps: Int, width: Int)
mediaAudio(to: FileFormat)
extract
zip
```
Each case has a display title ("Merge PDFs", "Convert to JPG", …).

### 3.2 `ActionCatalog`
`actions(for files: [URL], locator: ToolLocator) -> [CatalogEntry]`, where
`CatalogEntry = (action kind, title, requirements, availability)` and
`availability = .available | .unavailable([MissingTool])`, `MissingTool = (tool, installHint, enables)`.

Rules (by the formats of the selected files):
- **Convert:** targets common to every selected file (`Capabilities.targets` intersection);
  2+ images → pdf means "combine into one PDF". Availability per target from `Capabilities.tools`.
- **All PDFs:** merge (2+ files), split, extract, delete, rotate, text.
- **All video:** compress, trim (single file), gif, extract audio → ffmpeg (compress with a target
  size also needs ffprobe).
- **All archives:** extract (rar/7z need unar).
- **Anything:** zip.
- Unknown formats contribute nothing but zip.

`missingTools(for:locator:)` is the single place that turns "needs X" into user-facing text;
`homebrewInstalled(locator:)` checks for `brew` so every surface can say "install Homebrew first".

### 3.3 `ActionRunner`
`run(_ action: PeelAction, on files: [URL], output: URL?, planner: OutputPlanner,
locator: ToolLocator, cancel: CancelToken) -> [ActionOutcome]`
- Same output naming and `protecting: inputs + produced` rules as the CLI/Converter.
- Checks requirements first and fails each file with `PeelError.missingTool` (never starts work
  it can't finish).
- `CancelToken.cancel()` stops between files and terminates running tools
  (`InterruptCleanup.terminateRunningTools()`, new); a cancelled file reports `.cancelled`; its
  partial output is removed by the existing AtomicOutput cleanup.

### 3.4 Tool lookup override
`ToolLocator.standard` honours `PEEL_TOOL_PATH` (colon-separated) when set, replacing PATH +
Homebrew dirs. Used by tests to simulate "tool not installed" against the real binary, and
available to users with unusual setups.

## 4. Stage 2 — Finder Quick Actions

### 4.1 Installation
- `peel install-quick-actions [--dir <path>]` writes five `.workflow` bundles to
  `~/Library/Services` (default), each an Automator "Run Shell Script" service receiving files
  from Finder "as arguments", then refreshes the Services menu (`/System/Library/CoreServices/pbs -update`).
- The script embeds the absolute path of the installed `peel` (resolved from the running
  executable) and is a one-liner:
  `P='/Users/…/peel'; [ -x "$P" ] || { osascript … "peel isn't installed at $P — re-run install.sh"; exit 1; }; "$P" quick-action <name> "$@"`
- `peel uninstall-quick-actions` removes exactly the bundles it installed (names prefixed `peel - `).
- Re-installing replaces existing peel workflows (these are peel's own files, not user data).

### 4.2 `peel quick-action <name> <files…>` (hidden)
Runs in Swift via `ActionCatalog`/`ActionRunner`; talks to the user through a `QuickActionUI`
protocol: `choose(title:, items:) -> String?`, `notify(title:, message:)`, `alert(title:, message:, copyable:)`.
Production implementation uses `osascript` (`choose from list`, `display notification`,
`display dialog` with a "Copy Command" button that writes to the pasteboard via `pbcopy`).
Tests inject a fake UI.

| Quick Action | Behaviour |
|---|---|
| peel - Convert To… | Picker of targets for the selection; available ones first, unavailable ones listed as `webp — needs cwebp` (choosing one shows the install dialog). |
| peel - Merge PDFs | Requires 2+ PDFs; output `<first>-merged.pdf` next to the first. |
| peel - Split PDF | One file per page, for each selected PDF. |
| peel - Extract Here | `peel x` semantics for each selected archive. |
| peel - Zip | Zips the selection to `<first>.zip`. |

Result: one notification ("Converted 3 files", "Merged into report-merged.pdf"); any failure →
one dialog listing each failed file and message; a missing tool → dialog with the install command
and Copy button (plus the brew.sh hint if Homebrew is absent). Wrong selection (e.g. Merge on a
.png) → dialog explaining what the action needs.

## 5. Stage 3 — peel.app

### 5.1 Surfaces
- **Main window:** drop zone → file list (name, detected type, remove button) → action picker →
  options → **Run** → results list (✓ output with "Reveal in Finder", ✗ with message).
- **Menu-bar popover** (`MenuBarExtra`, window style): the same view, compact.
- **Dock icon / Open With:** files dropped on the Dock icon open the main window with them selected
  (`CFBundleDocumentTypes` = any item; `onOpenURL`/`application(_:open:)`).

### 5.2 Model (`PeelAppCore`, `@MainActor ObservableObject AppModel`)
State: `files: [URL]`, `entries: [CatalogEntry]` (recomputed on change), `selected action`,
option values, `isRunning`, `results: [ActionOutcome]`, `toolStatus: [Tool: URL?]`.
Intents: `add(urls)`, `remove(url)`, `clear()`, `select(entry)`, `run()`, `cancel()`,
`refreshTools()` (called when the window becomes active, so installing a tool and returning to the
app just works), `copyInstallCommand(for:)`.
`run()` executes `ActionRunner` off the main actor and publishes outcomes.

### 5.3 Options shown per action
convert: quality (lossy targets), width, height, dpi (PDF → image) · split: ranges (blank = every
page) · extract/delete: pages · rotate: 90/180/270 + optional pages · compress: optional target
size · trim: from/to · gif: fps, width · audio: format. Invalid input (bad page range, time) is
validated in the model and shown inline; Run is disabled until valid.

### 5.4 Missing dependencies in the app
- Unavailable entries appear greyed with a "Needs ffmpeg" badge; selecting one shows a panel:
  what it unlocks, the `brew install …` command, **Copy Command**, and (if `brew` is missing)
  a link to brew.sh.
- A **Tools** section (settings / about) lists every optional tool with ✓ path or ✗ + install
  command — the `peel doctor` equivalent, with a **Re-check** button.

### 5.5 Build & install
`scripts/build-app.sh`: `swift build -c release --product PeelApp`, assemble
`peel.app/Contents/{MacOS/peel, Info.plist}` (bundle id `dev.peel.app`, `LSMinimumSystemVersion`
13.0, document types), `codesign --force -s -` (ad-hoc), install to `~/Applications/peel.app`
(override with `APP_DIR`). `install.sh` runs it, then `peel install-quick-actions`.

## 6. Error handling
- All failures reuse `PeelError` messages (one line, with a fix).
- Quick Actions never exit silently: success → notification, failure → dialog.
- The app never shows raw `NSError` text for expected failures; unexpected errors show
  `localizedDescription` in the result row.
- Cancelling leaves no partial files (AtomicOutput + InterruptCleanup).

## 7. Testing
- **ConvertKit Actions:** catalog rules per selection mix; availability with
  `ToolLocator(searchPaths: [])`; runner outputs/naming/protection for every action; cancellation
  between files and during an ffmpeg run (no partial output).
- **Quick Actions:** workflow generator output (plist validity via `plutil -lint`, embedded peel
  path, NSServices entry); `quick-action` handler with a fake UI for each action, wrong selections,
  and missing tools; end-to-end: install into a temp dir and run each workflow headless with
  `automator -i` on fixture files.
- **Missing tools, real binary:** `PEEL_TOOL_PATH=<empty dir>` runs of `peel convert --to webp`,
  `peel media gif`, `peel x a.rar`, `peel formats`, `peel doctor` → exit codes and install hints.
- **App model:** `AppModel` tests (add/remove files → entries, option validation, run → results,
  unavailable entry → install panel data, refreshTools picks up a newly "installed" tool).
- **App bundle:** build script test that the produced bundle has a valid Info.plist and a signed,
  launchable executable (`codesign --verify`); SwiftUI views themselves are not unit-tested.

## 8. Build order
1. `PEEL_TOOL_PATH` override + missing-tool CLI tests (real binary).
2. Actions layer: `PeelAction`, `ActionCatalog`, `ActionRunner` (+ cancellation).
3. Quick Actions: generator, `install/uninstall-quick-actions`, `quick-action` handler + osascript UI,
   automator end-to-end tests.
4. `PeelAppCore` model.
5. `PeelApp` SwiftUI views + `build-app.sh` + install.sh/README updates.
