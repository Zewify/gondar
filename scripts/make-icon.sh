#!/usr/bin/env bash
# Renders the app icon: builds scripts/make-icon.swift with the shared mark geometry in App/Sources/GaugeMark.swift and runs it.
# Usage: ./scripts/make-icon.sh [output appiconset]
set -euo pipefail
cd "$(dirname "$0")/.."
tool="$(mktemp -d)/make-icon"
swiftc -O -o "$tool" App/Sources/GaugeMark.swift scripts/make-icon.swift
"$tool" "${1:-App/Resources/Assets.xcassets/AppIcon.appiconset}"
rm -rf "$(dirname "$tool")"
