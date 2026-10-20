#!/usr/bin/env bash
# Prepares a fresh clone: installs XcodeGen if needed, creates Config/Local.xcconfig and
# generates DrBar.xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
    if command -v brew >/dev/null; then
        echo "Installing XcodeGen with Homebrew"
        brew install xcodegen
    else
        echo "Please install XcodeGen: https://github.com/yonaskolb/XcodeGen" >&2
        exit 1
    fi
fi

if [ ! -f Config/Local.xcconfig ]; then
    cp Config/Local.xcconfig.example Config/Local.xcconfig
    echo "Created Config/Local.xcconfig. Set your bundle ID prefix there; a team ID is optional."
fi

xcodegen generate
echo "Done. Open DrBar.xcodeproj, or build with: xcodebuild -scheme DrBar build"
