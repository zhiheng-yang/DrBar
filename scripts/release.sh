#!/usr/bin/env bash
# Builds dist/DrBar-<version>.zip: the app itself, ready to publish on GitHub Releases. Unzipping it
# gives DrBar.app; there is nothing to install.
#
# The app is signed to run locally, with no developer team, so macOS asks once before it first
# opens it (README › Get started says how). With DEVELOPER_ID=1 it is signed with Developer ID and
# notarized instead, and opens at once; that needs a team of the paid Apple Developer Program in
# Config/Local.xcconfig (or DEVELOPMENT_TEAM in the environment) and a notary profile stored once with:
#   xcrun notarytool store-credentials drbar --apple-id <id> --team-id <team> --password <app-specific>
# NOTARY_PROFILE selects the profile (default: drbar). TRIAL=1 skips the checks of a release and
# notarization, and names the zip "-trial"; a release is built from a clean working tree.
set -euo pipefail
cd "$(dirname "$0")/.."

dist="dist"
profile="${NOTARY_PROFILE:-drbar}"
developer_id="${DEVELOPER_ID:-0}"
trial="${TRIAL:-0}"
version="$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)"
if [ -z "$version" ]; then
    echo "MARKETING_VERSION is missing from Config/Base.xcconfig." >&2
    exit 1
fi
team=""
if [ "$developer_id" = 1 ]; then
    team="${DEVELOPMENT_TEAM:-$(sed -n 's/^DEVELOPMENT_TEAM = //p' Config/Local.xcconfig 2>/dev/null || true)}"
    if [ -z "$team" ]; then
        echo "Set DEVELOPMENT_TEAM (in Config/Local.xcconfig or the environment) to sign with Developer ID." >&2
        exit 1
    fi
fi
if [ "$trial" != 1 ] && [ -n "$(git status --porcelain)" ]; then
    echo "Commit or stash your changes first: a release is built from a clean working tree." >&2
    exit 1
fi

rm -rf "$dist"
mkdir -p "$dist"
xcodegen generate --quiet

# Users' data belongs to the bundle ID, so a release goes out under the prefix committed in
# Config/Base.xcconfig, whatever Config/Local.xcconfig sets for local builds, and never under a
# placeholder.
prefix="$(sed -n 's/^BUNDLE_ID_PREFIX = //p' Config/Base.xcconfig)"
bundle_id="$(xcodebuild -project DrBar.xcodeproj -scheme DrBar -configuration Release \
    -destination 'generic/platform=macOS' BUNDLE_ID_PREFIX="$prefix" -showBuildSettings | sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER = //p' | head -1)"
if [ "$trial" != 1 ]; then
    case "$bundle_id" in
        "" | io.github.example.* | io.github.yourname.*)
            echo "\"$bundle_id\" is not a release bundle ID. Set BUNDLE_ID_PREFIX in Config/Base.xcconfig." >&2
            exit 1
            ;;
    esac
fi

if [ "$developer_id" = 1 ]; then
    echo "Archiving DrBar $version ($bundle_id), signed with Developer ID"
    xcodebuild -project DrBar.xcodeproj -scheme DrBar -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$dist/DrBar.xcarchive" BUNDLE_ID_PREFIX="$prefix" DEVELOPMENT_TEAM="$team" archive -quiet
    cat > "$dist/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$team</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$dist/DrBar.xcarchive" \
        -exportOptionsPlist "$dist/ExportOptions.plist" -exportPath "$dist/export" -quiet
    app="$dist/export/DrBar.app"
else
    # Signed to run locally, whatever team Config/Local.xcconfig names for local builds: a
    # development signature would run on this Mac only.
    echo "Archiving DrBar $version ($bundle_id), signed to run locally"
    xcodebuild -project DrBar.xcodeproj -scheme DrBar -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$dist/DrBar.xcarchive" BUNDLE_ID_PREFIX="$prefix" DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
        archive -quiet
    app="$dist/DrBar.xcarchive/Products/Applications/DrBar.app"
fi
codesign --verify --deep --strict "$app"

zip="$dist/DrBar-$version.zip"
[ "$trial" = 1 ] && zip="$dist/DrBar-$version-trial.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

# notarytool takes a zip; the ticket is then stapled to the app and the app zipped again, so it
# opens without a network check.
if [ "$developer_id" = 1 ] && [ "$trial" != 1 ]; then
    echo "Notarizing (this takes a few minutes)"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait | tee "$dist/notarization.log" || true
    if ! grep -q "status: Accepted" "$dist/notarization.log"; then
        echo "Notarization failed. For the reason: xcrun notarytool log <id> --keychain-profile $profile" >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose "$app"
    rm "$zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
fi

rm -rf "$dist/export" "$dist/ExportOptions.plist" "$dist/notarization.log"
echo "Done: $zip"
