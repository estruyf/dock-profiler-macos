#!/usr/bin/env bash
#
# Renders the README screenshots into docs/screenshots.
#
#   ./Scripts/make_screenshots.sh [output-dir]
#
# The shots come from the real views, with a set of demo profiles written to a
# throwaway store — your own profiles are never read or touched.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/screenshots}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export DOCKPROFILER_STORE_DIR="$WORK/store"
mkdir -p "$DOCKPROFILER_STORE_DIR" "$OUT"

# Everything but the @main entry point, which would clash with the tool's own.
SOURCES=$(find Sources/DockProfiler -name '*.swift' ! -name 'DockProfilerApp.swift')

# shellcheck disable=SC2086
swiftc -O -o "$WORK/screenshots" $SOURCES Scripts/Screenshots/main.swift

"$WORK/screenshots" "$OUT"
echo
echo "Screenshots in $OUT"
