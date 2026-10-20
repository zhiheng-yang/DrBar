#!/usr/bin/env bash
# Builds the debug app, puts it in ~/Applications and opens it from there, as the Finder would, so
# that Siri, Spotlight and Shortcuts know it; its log appears here and Ctrl-C quits it. A DrBar
# that is already running, such as an installed copy, is quit first; rendering snapshots leaves it
# alone.
#
# Usage: scripts/run.sh [--demo] [--zh] [--snapshots]
#   --demo       run on sample data in a temporary folder; your own data is not touched
#   --zh         run in Simplified Chinese
#   --snapshots  render the main views in light and dark to .build/snapshots, then quit
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
snapshots=0
for option in "$@"; do
    case "$option" in
        --demo) args+=(-DrBarDemo YES) ;;
        --zh) args+=(-AppleLanguages "(zh-Hans)") ;;
        --snapshots) snapshots=1 ;;
        *)
            echo "Usage: scripts/run.sh [--demo] [--zh] [--snapshots]" >&2
            exit 64
            ;;
    esac
done

xcodegen generate --quiet
xcodebuild -project DrBar.xcodeproj -scheme DrBar -configuration Debug -derivedDataPath .build/xcode \
    -destination "platform=macOS,arch=$(uname -m)" build -quiet
app=".build/xcode/Build/Products/Debug/DrBar.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "$snapshots" = 1 ]; then
    # The app is sandboxed, so it renders into its own container; the files are moved out after.
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    rendered="$HOME/Library/Containers/$bundle_id/Data/tmp/snapshots"
    rm -rf "$rendered" .build/snapshots
    # The default blue accent, so that the images look the same on every Mac.
    "$app/Contents/MacOS/DrBar" -DrBarSnapshots "$rendered" -AppleAccentColor 4 ${args[@]+"${args[@]}"}
    mv "$rendered" .build/snapshots
    # Siri and Shortcuts should only know the copy that is run.
    "$lsregister" -u "$app" 2>/dev/null || true
    echo "Snapshots in .build/snapshots"
else
    # Two copies would both sit in the menu bar, and with the same bundle ID write the same data.
    if pkill -x DrBar; then
        while pgrep -x DrBar >/dev/null; do sleep 0.2; done
    fi
    # An app in a hidden build folder, started as a plain process, is one Siri has never heard of:
    # it runs from Applications, and only that copy stays registered.
    installed="$HOME/Applications/DrBar.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$installed"
    ditto "$app" "$installed"
    "$lsregister" -u "$app" 2>/dev/null || true
    "$lsregister" -f "$installed"
    log="$(tty)" || log=/dev/null
    trap 'pkill -x DrBar || true' INT TERM HUP
    open -g -W --stdout "$log" --stderr "$log" "$installed" ${args[@]+--args "${args[@]}"}
fi
