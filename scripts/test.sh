#!/usr/bin/env bash
# Runs the core tests and the installer tests, builds the app so a compile error anywhere fails the run, then tests the app's gondar-feed.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Core && swift test --quiet)
./scripts/test-install.sh
./scripts/build.sh Debug >/dev/null
./scripts/test-feed.sh
