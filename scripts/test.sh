#!/usr/bin/env bash
# Runs the test suite (extra arguments go to `swift test`, e.g. --filter PageRangeTests).
# On Macs with only the Command Line Tools (no Xcode), SwiftPM must be told where Swift Testing
# lives, or it builds the tests and then silently runs none of them.
set -euo pipefail
cd "$(dirname "$0")/.."
# Some tests drive the real `peel` binary (e.g. Ctrl-C handling), so make sure it's current.
# Tests leave their temp folders for inspection; tidy ones older than a day.
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'peel-tests-*' -mtime +0 -exec rm -rf {} + 2>/dev/null || true
for product in peel PeelApp; do
  if ! out="$(swift build --product "$product" 2>&1)"; then echo "$out" | grep -E "error|warning: " ; exit 1; fi
done
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ ! -d /Applications/Xcode.app ] && [ -d "$CLT/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
    "$@"
fi
exec swift test "$@"
