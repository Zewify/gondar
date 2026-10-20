#!/usr/bin/env bash
# Builds Release, replaces /Applications/Gondar.app with it, and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$(./scripts/build.sh Release | tail -1)"
osascript -e 'quit app "Gondar"' >/dev/null 2>&1 || true
# Quitting is asynchronous; opening while the old copy is still exiting fails with error -600.
for _ in {1..50}; do pgrep -xq Gondar || break; sleep 0.2; done
rm -rf "/Applications/Gondar.app"
ditto "$app" "/Applications/Gondar.app"
open "/Applications/Gondar.app"
echo "Installed /Applications/Gondar.app"
