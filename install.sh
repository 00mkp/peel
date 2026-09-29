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

echo
"$BIN/peel" doctor || true
