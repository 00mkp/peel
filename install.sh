#!/usr/bin/env bash
# Builds peel in release mode and installs it to $PREFIX/bin (default ~/.local/bin).
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
case "$PREFIX" in /*) ;; *) PREFIX="$(pwd)/$PREFIX" ;; esac   # relative to where you ran it; the record must hold absolute paths
APP_DIR="${APP_DIR:-$HOME/Applications}"
case "$APP_DIR" in /*) ;; *) APP_DIR="$(pwd)/$APP_DIR" ;; esac
export APP_DIR
cd "$(dirname "$0")"

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
    echo "app_dir=$APP_DIR"
    echo "prefix=$PREFIX"
    echo "source=$(pwd)"
    echo "version=$(tr -d '[:space:]' < VERSION)"
  } > "$RECORD_DIR/install.conf"
fi

echo
"$BIN/peel" doctor || true
