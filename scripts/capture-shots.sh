#!/usr/bin/env bash
# Captures zewify.com's screenshots from a Debug build in demo mode (`-GondarDemo live`: a made-up account and numbers, no network).
# Never capture a real account: its panel shows the email and organisation name.
# The demo runs beside an installed Gondar, under the same name and bundle ID, so it is found and quit by process ID only.
# Needs the Accessibility permission for the terminal (the System Events click). Output: build/shots/panel.png and window.png, 1x on a 1x display.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/shots; mkdir -p "$out"
app="$(./scripts/build.sh Debug | tail -1)"
binary="$PWD/$app/Contents/MacOS/Gondar"
pkill -f "^$binary" >/dev/null 2>&1 || true; sleep 1
open -n "$app" --args -GondarDemo live
pid=""
for _ in $(seq 1 40); do pid="$(pgrep -f "^$binary" | head -1 || true)"; [ -n "$pid" ] && break; sleep 0.25; done
[ -n "$pid" ] || { echo "The demo did not start" >&2; exit 1; }
trap 'kill "$pid" >/dev/null 2>&1 || true' EXIT

# Each window's ID by its layer: 3 is the pop-out (a floating window, opened at launch), 101 the menu bar panel.
window() { swift scripts/window-id.swift "$pid" | awk -v layer="$1" '$2 == layer { print $1; exit }'; }
wait_for() { for _ in $(seq 1 40); do id="$(window "$1")"; [ -n "$id" ] && { echo "$id"; return; }; sleep 0.25; done; echo "No window on layer $1" >&2; exit 1; }

win="$(wait_for 3)"; sleep 1  # the pop-out fits its height to its rows once, on first layout
screencapture -x -o -l "$win" "$out/window.png"
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to click menu bar item 1 of menu bar 2" >/dev/null
sleep 1.5
screencapture -x -o -l "$(wait_for 101)" "$out/panel.png"
sips -g pixelWidth -g pixelHeight "$out/panel.png" "$out/window.png"
