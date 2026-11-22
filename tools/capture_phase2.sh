#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/home/ubuntu/bin/godot}"
OUTPUT="${FACTORY_CAPTURE_DIR:-/home/ubuntu/specs/shots/v5}"
mkdir -p "$OUTPUT"

for scenario in \
	green-preview \
	red-overlap \
	red-miner \
	belt-to-smelter \
	pole-turn \
	hill-belt \
	demo-factory
do
	FACTORY_CAPTURE_DIR="$OUTPUT" "$GODOT" --path "$ROOT" --windowed --resolution 1600x900 \
		--rendering-method gl_compatibility -- --new-game "--capture-v5-$scenario"
done
