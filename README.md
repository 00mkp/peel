# peel

Free, open-source, local-only file converter and toolkit for macOS. Convert images, PDFs,
audio/video, subtitles and archives from the terminal — nothing is ever uploaded.

## Install

Requires macOS 13+ and Xcode or the Swift command-line tools.

```bash
git clone <this repo> peel && cd peel
./install.sh            # installs to ~/.local/bin (override with PREFIX=/usr/local ./install.sh)
```

Optional extras unlock more formats — `peel doctor` shows what's installed:

```bash
brew install ffmpeg webp libavif unar librsvg
```

| Tool | Unlocks |
|---|---|
| ffmpeg | video/audio conversion, trim, compress, GIF |
| webp / libavif | WebP / AVIF output |
| unar | RAR and 7z extraction |
| librsvg | SVG input |

PDF tools, JPG/PNG/HEIC/TIFF/BMP/GIF images, subtitles, zip and tar need nothing extra.

## Examples

```bash
# Convert (format detected automatically)
peel convert IMG_0412.HEIC --to jpg
peel convert *.png --to webp --quality 80 --width 1600
peel convert scan.pdf --to png --dpi 150          # one image per page
peel convert a.jpg b.jpg c.jpg --to pdf           # one combined PDF
peel convert talk.mov --to mp4
peel convert subs.srt --to vtt

# PDFs
peel pdf merge a.pdf b.pdf c.pdf -o combined.pdf
peel pdf split big.pdf                            # one file per page
peel pdf split big.pdf --pages 1-3,7-9            # one file per range
peel pdf extract big.pdf --pages 2-5
peel pdf delete big.pdf --pages 4,6
peel pdf rotate big.pdf --by 90 --pages 1,3
peel pdf reorder big.pdf --order 3,1,2,4-
peel pdf text big.pdf
peel pdf info big.pdf

# Media (ffmpeg)
peel media trim clip.mp4 --from 0:10 --to 0:45
peel media compress clip.mov --size 25MB
peel media audio clip.mp4 --to mp3
peel media gif clip.mp4 --fps 12 --width 480

# Archives
peel x anything.zip                               # also tar.gz, tar.xz, gz, rar, 7z
peel zip folder/ notes.txt -o bundle.zip

# Help
peel formats photo.heic                           # what can this become?
peel doctor
```

## Finder Quick Actions

`./install.sh` adds these to Finder's right-click menu (Quick Actions / Services):
**Peel - Convert To…**, **Merge PDFs**, **Split PDF**, **Extract Here**, **Zip**.
Results appear as notifications; problems (including a missing optional tool, with the exact
`brew install` command) appear as dialogs. Manage them with:

```bash
peel install-quick-actions
peel uninstall-quick-actions
```

## Peel.app

`./install.sh` also builds `~/Applications/Peel.app` (or run `scripts/build-app.sh`; set `APP_DIR`
to install elsewhere). Peel lives in the menu bar — look for the peel-twist icon. Click it, drop
files into the popover (or use **Choose Files…**), pick an action, adjust options and press Run.

- **Open Window** in the popover gives a larger window; it also opens when you open Peel again from
  Finder/Spotlight or open files with it. The Dock icon shows only while a Peel window is open.
- The gear menu has **Settings…** (optional tools, **Open at Login**) and **Quit Peel**; with a window
  open, Settings is also in the Peel menu (⌘,).
- Actions that need a tool you don't have are listed separately with the install command; Peel
  re-checks whenever you come back to it.

## Behaviour

- Output goes next to the input unless you pass `-o` (a file, or a folder — end it with `/`).
- Existing files are never overwritten: you get `name 2.ext`. `--force` overwrites, but never an input.
- Batches keep going when one file fails; the exit code is `1` if anything failed, `2` for usage errors.
- Page ranges: `3`, `1-3,5`, `8-` (to the end), `5-3` (backwards).
- Ctrl-C stops cleanly and leaves no half-written files.
- Set PEEL_TOOL_PATH (colon-separated folders) to control where peel looks for optional tools.

## Development

```bash
swift build
scripts/test.sh          # runs the tests (use this rather than bare `swift test`: with only the
                         # Command Line Tools installed, `swift test` silently runs no tests)
```

MIT licensed.
