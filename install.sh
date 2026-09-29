#!/usr/bin/env bash
# Builds peel in release mode and installs it to $PREFIX/bin (default ~/.local/bin).
set -euo pipefail
cd "$(dirname "$0")"

PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"

echo "Building peel (release)…"
swift build -c release
mkdir -p "$BIN"
install -m 755 "$(swift build -c release --show-bin-path)/peel" "$BIN/peel"
echo "Installed peel to $BIN/peel"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    echo
    echo "note: $BIN is not on your PATH. Add this to ~/.zshrc:"
    echo "  export PATH=\"$BIN:\$PATH\""
    ;;
esac

echo
echo "Installing Finder Quick Actions…"
"$BIN/peel" install-quick-actions

echo
scripts/build-app.sh

# Record where this install came from, so `peel update` can pull and reinstall it later.
# (`peel update <archive>` sets PEEL_NO_RECORD: its unpacked temp dir must never be recorded.)
if [ "${PEEL_NO_RECORD:-0}" != "1" ]; then
  RECORD_DIR="$HOME/Library/Application Support/peel"
  mkdir -p "$RECORD_DIR"
  {
    echo "app_dir=${APP_DIR:-$HOME/Applications}"
    echo "prefix=$PREFIX"
    echo "source=$(pwd)"
    echo "version=$(tr -d '[:space:]' < VERSION)"
  } > "$RECORD_DIR/install.conf"
fi

echo
"$BIN/peel" doctor || true
