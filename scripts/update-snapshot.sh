#!/usr/bin/env bash
# Refreshes the ccfddl snapshot bundled with the app (App/Resources/allconf.yml, and the acceptance
# rates in App/Resources/allacc.yml) and checks that both parse. The app uses the snapshot only on a
# first launch without network.
#
# Usage: scripts/update-snapshot.sh
set -euo pipefail

cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
refreshed=()

# Downloads `url` into `dest` under a three-line header, unless it is unchanged.
refresh() {
    local url="$1" dest="$2" title="$3" name
    name="$(basename "$dest")"
    echo "Downloading $url"
    curl --fail --silent --show-error --location --compressed --max-time 120 \
        --user-agent "DrBar snapshot script (+https://github.com/zhiheng-yang/DrBar)" \
        --output "$work/$name" "$url"
    # The first three lines are the header written below.
    if [ -f "$dest" ] && tail -n +4 "$dest" | cmp -s - "$work/$name"; then
        echo "$dest is up to date."
        return
    fi
    if [ -f "$dest" ]; then cp "$dest" "$work/$name.previous"; fi
    {
        # The app reads the date from this first line.
        echo "# ccfddl $title $(date -u +%Y-%m-%d)"
        echo "# Source: $url"
        echo "# Data by the ccfddl contributors, MIT License: https://github.com/ccfddl/ccf-deadlines"
        cat "$work/$name"
    } > "$dest"
    refreshed+=("$dest")
}

refresh "https://ccfddl.com/conference/allconf.yml" "App/Resources/allconf.yml" "snapshot"
refresh "https://ccfddl.com/conference/allacc.yml" "App/Resources/allacc.yml" "acceptance rates snapshot"
[ "${#refreshed[@]}" -gt 0 ] || exit 0

echo "Checking that the snapshot parses"
if ! swift test --package-path Packages/DrBarKit --filter BundledSnapshotTests; then
    echo "The new snapshot does not pass the checks; keeping the previous one." >&2
    for dest in "${refreshed[@]}"; do
        previous="$work/$(basename "$dest").previous"
        if [ -s "$previous" ]; then cp "$previous" "$dest"; else rm -f "$dest"; fi
    done
    exit 1
fi

for dest in "${refreshed[@]}"; do
    echo "Updated $dest ($(wc -c < "$dest" | tr -d ' ') bytes)"
done
