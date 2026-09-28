# peel — Design Spec

**Date:** 2026-09-28
**Status:** Draft for review
**Scope of this spec:** Stage 1 (ConvertKit engine + `peel` CLI) in full; Stages 2–3 sketched.

## 1. Purpose

`peel` is a free, open-source, local-only file converter and file toolkit for macOS — a
from-scratch alternative to paid drag-and-drop converters. It converts between common image,
PDF, audio/video, subtitle, and archive formats, and provides everyday tools (merge/split PDFs,
trim video, extract archives).

### What the user said
- Wants a free alternative to a $15 converter app; open source.
- Primarily for personal use first, growing into something others can install and run.
  Does **not** need Homebrew distribution or polish-grade OSS process.
- All categories are wanted; **PDF management (especially merge/split) is the most-used feature.**
- Must be backed by a CLI usable from the terminal; a GUI is desired on top.
- Archive extraction should work like oh-my-zsh's `x`: one command that extracts anything.
- GUI delivered in stages: CLI → Finder Quick Actions → SwiftUI drop-window app.

### Assumptions (open to correction)
- macOS only (13 Ventura+, Apple Silicon and Intel).
- Nice-to-haves that turn out to be hard are deferred rather than forced into v1.
- All processing is local; no network access ever.

### Success criteria (Stage 1)
1. On a clean Mac, `git clone` + `./install.sh` produces a working `peel` on `PATH`.
2. All `peel pdf` commands and image/subtitle/PDF conversions work with **zero** third-party
   dependencies.
3. Media and exotic-format features work when optional tools are installed and fail with a
   clear install hint when they are not.
4. `swift test` passes with no binary fixtures in the repo.

### Non-goals (v1)
- PDF → DOCX (needs LibreOffice; possible later optional backend).
- Creating RAR archives (proprietary format; extraction only).
- PDF compression (Quartz filter results are poor; may ship later as experimental).
- Windows/Linux support, Homebrew tap, signed/notarized binaries.
- Any cloud/network features.

## 2. Architecture

A single Swift package (Swift 6 toolchain, `swift-tools-version: 5.10`+, platform `.macOS(.v13)`)
in one git repo.

```
peel/
├─ Package.swift
├─ Sources/
│  ├─ ConvertKit/            library — all conversion logic, no UI/CLI knowledge
│  │  ├─ Core/               format detection, capability registry, page ranges,
│  │  │                      output naming, external-tool lookup, errors
│  │  ├─ PDF/                PDFKit backend
│  │  ├─ Image/              ImageIO / CoreImage backend (+ optional cwebp/avifenc)
│  │  ├─ Media/              ffmpeg subprocess backend
│  │  ├─ Archive/            ditto / tar / unzip / unar backend
│  │  └─ Subtitle/           pure-Swift SRT/VTT/TXT backend
│  └─ peel/                  executable — swift-argument-parser CLI over ConvertKit
├─ Tests/
│  ├─ ConvertKitTests/
│  └─ peelTests/
├─ install.sh
├─ README.md
└─ LICENSE                   MIT
```

Later stages add `QuickActions/` (Stage 2) and `App/` (Stage 3) to the same repo.

### Principles
- **Engine/UI separation.** ConvertKit exposes a Swift API; the CLI, Quick Actions, and app are
  thin shells. Every capability lives in ConvertKit exactly once.
- **Independent backends.** Each backend owns one category and does not depend on others.
  A missing external tool disables only the features that need it.
- **One capability registry.** A single table declares which input formats convert to which
  output formats and which backend (and external tool, if any) handles each pair. `peel formats`,
  conversion routing, and future GUI menus all read from it.
- **Safe outputs.** Never overwrite unless `--force`.
- **Local only.** No network I/O anywhere.

## 3. Components

### 3.1 Core
- **`FileFormat`** — enum of known formats (jpg, png, heic, tiff, bmp, gif, webp, avif, svg, pdf,
  txt, mp4, mov, mkv, webm, avi, wmv, mp3, m4a, wav, flac, ogg, opus, aiff, wma, srt, vtt, zip,
  tar, gz, tgz, rar, 7z). Detected by file extension, with UTType as fallback.
- **`Capabilities`** — registry mapping `(from, to)` → backend + required external tool (if any).
  API: `targets(for: FileFormat) -> [FileFormat]`, `isAvailable(...)` (considers installed tools).
- **`PageRange`** — parses `1-3,5,8-` (1-based, inclusive, open-ended `N-` = through last page);
  validates against page count; preserves the user's order and allows repeats (needed by `reorder`).
- **`OutputPlanner`** — given inputs, target extension, and optional `-o` (file or directory),
  produces output URLs. Default: same directory as input, same basename, new extension. On
  collision without `--force`, appends ` 2`, ` 3`, … before the extension. Multi-output
  operations (split, PDF→images) use `name-p1.ext` style suffixes or ranges (`name-p1-3.pdf`).
- **`ExternalTool`** — locates `ffmpeg`, `ffprobe`, `cwebp`, `avifenc`, `unar`, `rsvg-convert`
  by searching `PATH` plus `/opt/homebrew/bin` and `/usr/local/bin` (needed because Finder
  Quick Actions run with a minimal `PATH`). Runs processes with captured stdout/stderr.
- **`PeelError`** — typed errors: `unsupportedConversion(from:to:)`, `missingTool(name:installHint:)`,
  `invalidPageRange(String)`, `pageOutOfBounds(page:count:)`, `unreadableFile(URL)`,
  `toolFailed(name:exitCode:lastLine:)`, `outputExists(URL)`. Each has a user-facing message.

### 3.2 PDF backend (PDFKit — no dependencies)
- `merge([URL]) -> URL`
- `split(URL, ranges: [PageRange]?) -> [URL]` — no ranges = one file per page.
- `extract(URL, pages:) -> URL`
- `delete(URL, pages:) -> URL`
- `rotate(URL, degrees: 90|180|270, pages:?) -> URL` (default all pages; `-90` accepted as 270)
- `reorder(URL, order: PageRange) -> URL` — order may omit pages (they are dropped) or repeat them.
- `text(URL) -> URL` — plain-text extraction.
- `info(URL) -> PDFInfo` — page count, page size, title/author, encrypted flag.
- `toImages(URL, format: png|jpg, dpi: Int = 300) -> [URL]`
- `fromImages([URL]) -> URL` — one page per image, page sized to image.
- `fromText(URL) -> URL` — TXT → paginated PDF (Letter, system monospace font).
- Tools that modify a PDF write a new file; input is never modified in place. Default output
  names (when no `-o`): `<first>-merged.pdf`, `<name>-p<N>.pdf` / `<name>-p<A>-<B>.pdf` (split),
  `<name>-extract.pdf`, `<name>-deleted.pdf`, `<name>-rotated.pdf`, `<name>-reordered.pdf`,
  `<name>.txt` (text), `<name>-p<N>.<ext>` (to images). All pass through OutputPlanner's
  collision handling.
- Encrypted PDFs: fail with a clear error (no password support in v1).

### 3.3 Image backend (ImageIO / CoreImage)
- Native read: jpg, png, heic, tiff, bmp, gif, webp, avif (read support per macOS version).
- Native write: jpg, png, heic, tiff, bmp, gif.
- WebP write via `cwebp`; AVIF write via `avifenc` (optional tools).
- SVG input rasterized via `rsvg-convert` (optional tool); SVG output not supported.
- Options: `--quality 1-100` (lossy formats), `--width`/`--height` (resize preserving aspect ratio
  if only one is given; never upscale unless both are given explicitly).
- EXIF orientation is applied on conversion so output is visually upright.

### 3.4 Media backend (ffmpeg — optional)
- `convert` between video formats (mp4, mov, mkv, webm, avi, wmv), audio formats (mp3, m4a, wav,
  flac, ogg, opus, aiff, wma), and video → gif.
- `trim(from:to:)` — timestamps as `SS`, `MM:SS`, or `HH:MM:SS(.ms)`; stream copy when possible.
- `compress(targetSize:?)` — default: H.264 CRF 28; with `--size`, two-pass bitrate targeting
  using duration from `ffprobe`.
- `audio(to:)` — extract audio track.
- `gif(fps: 12, width: 480)` — palette-generating two-step for quality.
- Surfaces only the last meaningful stderr line on failure (full output with `--verbose`).

### 3.5 Archive backend
- `extract(URL)` — into a new folder next to the archive named after it (collision-safe).
  zip → `ditto -x -k`; tar/tar.gz/tgz/gz → `tar`/`gunzip`; rar/7z → `unar` (optional).
- `zip([URL], output:)` → `ditto -c -k --sequesterRsrc --keepParent`.
- `tar.gz` creation via `tar -czf`.

### 3.6 Subtitle backend (pure Swift)
- Parse SRT and VTT into a common cue model; write SRT, VTT, or TXT (text only, cues joined by
  newlines). Handles `,` vs `.` millisecond separators, BOM, CRLF, and VTT headers/cue settings
  (settings dropped when writing SRT).

## 4. CLI (`peel`)

Built with `swift-argument-parser`.

```
peel convert <files...> --to <fmt> [-o <path>] [--quality N] [--width N] [--height N]
                                    [--dpi N] [--force] [--verbose]
peel pdf merge <files...> -o <file>
peel pdf split <file> [--pages <ranges>]
peel pdf extract <file> --pages <ranges> [-o <file>]
peel pdf delete <file> --pages <ranges> [-o <file>]
peel pdf rotate <file> --by <90|180|270|-90> [--pages <ranges>] [-o <file>]
peel pdf reorder <file> --order <ranges> [-o <file>]
peel pdf text <file> [-o <file>]
peel pdf info <file>
peel media trim <file> --from <t> --to <t> [-o <file>]
peel media compress <file> [--size <e.g. 25MB>] [-o <file>]
peel media audio <file> --to <fmt> [-o <file>]
peel media gif <file> [--fps N] [--width N] [-o <file>]
peel x <archive> [-o <dir>]
peel zip <paths...> -o <file.zip|file.tar.gz>
peel formats [<file>]            # no file: print full capability table
peel doctor                      # optional tools: found/missing + install hint
```

- `peel convert` with multiple images and `--to pdf` produces **one** combined PDF.
  With any other target, each input converts independently.
- If `pdf merge` is given no `-o`, output is `<first-input>-merged.pdf`.
- Batch semantics: process every input; on failure, report and continue. Final summary line:
  `converted 9/10 files (1 failed)`.
- Exit codes: `0` all succeeded, `1` one or more inputs failed, `2` usage error.
- Output: one line per produced file (`✓ photo.jpg`), errors to stderr (`✗ bad.heic: <message>`).
  No colors when stdout is not a TTY.

## 5. Data flow

```
CLI args ──parse──▶ Job(inputs, operation, options, output)
                      │
                      ▼
          FileFormat detection ──▶ Capabilities lookup ──▶ tool availability check
                      │                                        │ missing → PeelError.missingTool
                      ▼
               OutputPlanner (collision-safe URLs)
                      │
                      ▼
               Backend operation (PDFKit / ImageIO / ffmpeg / ditto / Swift)
                      │
                      ▼
               Result per input (success URLs or PeelError) ──▶ CLI prints + exit code
```

Operations are synchronous per file in Stage 1; batch runs sequentially. (Concurrency can be
added later without API changes because each file is independent.)

## 6. Error handling

- Every failure maps to a `PeelError` with a one-line user-facing message and, where applicable,
  a fix (`brew install ffmpeg`, `run 'peel formats file.xyz'`).
- Partial outputs from a failed operation are deleted.
- Inputs are never modified.

## 7. Testing

- Framework: Swift Testing (`swift test`).
- **No binary fixtures committed.** Tests generate inputs at runtime: PDFs via PDFKit/CoreGraphics
  (pages labelled with their number so order can be asserted via text extraction), images via
  CoreGraphics, subtitles as strings, archives by zipping generated files.
- Coverage:
  - Core: PageRange parsing/validation, OutputPlanner naming and collisions, Capabilities lookups.
  - PDF: page counts and order after merge/split/extract/delete/reorder; rotation values;
    text extraction; images↔PDF round trip.
  - Image: output format (UTType) and dimensions after convert/resize; orientation handling.
  - Subtitle: SRT↔VTT round trips, edge cases (BOM, CRLF, cue settings).
  - Archive: zip → extract round trip (built-in tools).
  - Media / optional-tool paths: run only when the tool is installed; otherwise skipped
    with a note.
  - CLI: argument parsing, exit codes, output lines.

## 8. Installation

- `install.sh`: `swift build -c release`, then copy `.build/release/peel` to `~/.local/bin`
  (or `$PREFIX/bin` if `PREFIX` is set); warns if the target dir is not on `PATH`.
- README: what it does, install, examples, optional tools (`brew install ffmpeg webp libavif unar librsvg`),
  `peel doctor`.
- License: MIT.

## 9. Build order within Stage 1

1. Package skeleton, Core (FileFormat, PageRange, OutputPlanner, PeelError, ExternalTool), CLI shell.
2. PDF backend + `peel pdf *` + PDF conversions.
3. Image backend + `peel convert` for images.
4. Subtitle backend.
5. Archive backend + `peel x` / `peel zip`.
6. Media backend + `peel media *`.
7. `peel formats`, `peel doctor`, `install.sh`, README.

## 10. Later stages (sketch — each gets its own spec)

**Stage 2 — Finder Quick Actions.** Right-click actions: *Merge PDFs*, *Split PDF*, *Convert to…*,
*Extract Here*. "Convert to…" reads targets from `peel formats` and shows a picker. Installed via
`peel install-quick-actions` into `~/Library/Services`.

**Stage 3 — SwiftUI app.** Small window + menu-bar extra; drop files, choose target/tool and
options, see per-file progress and results. Links ConvertKit directly.
