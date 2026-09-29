# peel — Action Wheel + Menu-Bar-Only App — Design Spec

**Date:** 2026-09-29
**Builds on:** Stages 1–3 (`2026-09-28-peel-design.md`, `2026-09-28-peel-stage2-3-design.md`)

## 1. Purpose

Make Peel cognitively lightweight: no standalone window, no Dock icon. Two surfaces only:

1. **Action wheel** — drag files anywhere (Finder, Desktop…), hold **Shift**, and a wheel of one-step
   actions appears at the cursor. Drop on an action to run it; a notification reports the result.
   The centre slot, **More…**, hands the files to the menu-bar panel.
2. **Menu-bar panel** — the existing panel (drop area → files → action + options → Run → results),
   now reachable by **dropping files onto the menu-bar icon**, **pinnable** so it stays open while
   you drag from Finder, with **Settings inside it** (gear).

### What the user said
- "The whole point was that this was lightweight cognitively and easy to enter from a UI standpoint;
  a full window app (in the Dock, standalone) is not that."
- Wants a Tangerine-style Shift-drag wheel "even for just the most common one-step stuff", everything
  else in the menu bar, with the panel able to stay open for true drag-and-drop; remove the window.
- A macOS permission prompt, if needed, is acceptable.

### Success criteria
1. No Peel window exists except the panel (popover), a fallback floating panel when the menu-bar
   icon is hidden, and the wheel overlay. No Dock icon ever (LSUIElement).
2. Shift while dragging files shows a wheel of ≤ 6 available one-step actions for those files plus
   **More…**; dropping runs the action with default options and posts a notification (success or
   the failure message). Releasing without dropping on a slot does nothing.
3. Dropping files on the menu-bar icon opens the panel with them loaded. The panel can be pinned
   (stays open when clicking elsewhere). Opening Peel again / "Open With" opens the panel.
4. Settings (tools, Open at Login) and Quit are inside the panel's gear menu.
5. All non-UI logic (drag detection state machine, wheel slot choice, quick-run, notification text)
   is unit-tested; the AppKit/SwiftUI shell builds and is smoke-tested by launching.

### Non-goals
- A Finder extension; keyboard shortcuts for wheel slots; per-slot options in the wheel.
- Guaranteeing the wheel appears over full-screen apps of other Spaces beyond standard
  `.canJoinAllSpaces` behaviour.

## 2. Design

### 2.1 Drag detection (permission-light)
A 30 ms timer samples state that any app may read: `NSEvent.pressedMouseButtons`,
`NSEvent.modifierFlags`, `NSEvent.mouseLocation`, and the drag pasteboard's `changeCount`/types.
A pure `DragDetector` state machine turns samples into `showWheel(at:)` / `hideWheel`:
- On mouse-down, remember the drag pasteboard's change count.
- While the button is down: when the count has changed (a drag started), it carries file URLs, and
  Shift is held → show once.
- On mouse-up → hide (the controller delays hiding ~0.35 s so a drop in progress completes).
Once shown, the wheel stays until mouse-up even if Shift is released. Reading the dragged files'
URLs may trigger macOS's pasteboard-privacy prompt; that is the accepted one-time permission.

### 2.2 Wheel contents (`WheelMenu`)
From `ActionCatalog.entries(for:)`, keep **available** entries that have a one-step default action:
convert(any target that isn't already every file's format) → default options; Merge (2+ PDFs);
Split (every page); Rotate 90°; Compress (no size); GIF (12 fps, 480 px); Extract Audio (MP3);
Extract (archives); Zip. Rank: Merge, Extract, Compress, GIF, MP3, Split, conversions (JPG, PNG, PDF,
MP4, MP3, M4A, WebP, HEIC, GIF, TXT, VTT, SRT, then others), Rotate. Take up to 5, then Zip last
(total ≤ 6). Labels are short ("Merge", "→ JPG", "Zip").

### 2.3 Quick run
`AppModel.runQuick(kind, on:)` loads the files into the panel state (files + selection) and runs
the default action, so results also appear in the panel. Busy → returns nil and the wheel posts
"Peel is busy". `QuickSummary.text(for:rows:)` produces notification text: "Merged → a-merged.pdf",
"Converted 3 files", or "Couldn't finish: a.pdf: can't read …".

### 2.4 Shell (AppKit)
- `StatusController`: `NSStatusItem` with the peel icon; a transparent drop view over the button
  accepts file drops (→ model.add + show panel) and forwards clicks (toggle panel).
- Panel = `NSPopover` hosting the SwiftUI panel view (`.transient`; pinned → `.applicationDefined`).
  If the status item isn't on screen (menu-bar overflow), a floating utility `NSPanel` shows the
  same view instead.
- `WheelController`: the sampler + a borderless, non-activating, transparent overlay `NSPanel`
  hosting `WheelView` (slots in a circle, each an `onDrop` target, centre More…).
- `Notifier`: `UNUserNotificationCenter` (asks once); clicking a notification opens the panel.
- The standalone main window, its Dock icon and the separate Settings window are removed.

## 3. Testing
DragDetector sequences (no drag, drag without Shift, Shift before/after drag start, stays shown after
Shift release, hides on mouse-up, one show per drag, non-file drags ignored); WheelMenu per file mix,
missing tools, ≤ 6 slots, no same-format conversions, Zip last; runQuick results/busy/state;
QuickSummary texts. Shell: build + launch smoke (no windows at launch, policy accessory). Real drags
can't be synthesized here — the owner tries the wheel by hand.
