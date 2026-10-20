#!/usr/bin/env bash
# Adds new UI strings and Siri phrases to the String Catalogs and marks removed ones as stale.
# Translations are then added in Xcode's catalog editor.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="$(mktemp -d)"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The build is registered with Launch Services as it is made; it goes with its folder, so that Siri
# and Shortcuts know only the app that is run.
trap '"$lsregister" -u "$derived/Build/Products/Debug/DrBar.app" 2>/dev/null || true; rm -rf "$derived"' EXIT

xcodegen generate --quiet
xcodebuild -project DrBar.xcodeproj -scheme DrBar -configuration Debug \
    -derivedDataPath "$derived" SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO build -quiet

intermediates="$derived/Build/Intermediates.noindex"
sync() {
    local catalog="$1" target="$2"
    if [ -z "$(find "$intermediates" -path "*/Debug/$target.build/*" -name '*.stringsdata' -print -quit)" ]; then
        echo "The build produced no strings for $target." >&2
        exit 1
    fi
    find "$intermediates" -path "*/Debug/$target.build/*" -name '*.stringsdata' -print0 |
        xargs -0 xcrun xcstringstool sync "$catalog" --stringsdata
    echo "Updated $catalog"
}
sync App/Resources/Localizable.xcstrings DrBar
sync App/Resources/AppShortcuts.xcstrings DrBar
sync Packages/DrBarKit/Sources/DrBarUI/Resources/Localizable.xcstrings DrBarUI
