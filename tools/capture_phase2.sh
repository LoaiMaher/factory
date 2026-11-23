#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$HOME/bin/godot-4.7.2}"
OUTPUT="${FACTORY_CAPTURE_DIR:-/home/ubuntu/specs/shots/v6}"
mkdir -p "$OUTPUT"

for scenario in \
	green-preview \
	red-overlap \
	red-miner \
	belt-to-smelter \
	belt-port-closeup \
	pole-turn \
	hill-belt \
	demo-factory
do
	FACTORY_CAPTURE_DIR="$OUTPUT" "$GODOT" --path "$ROOT" --windowed --resolution 1600x900 \
		--rendering-method gl_compatibility -- --new-game "--capture-v5-$scenario"
done

FACTORY_CAPTURE_DIR="$OUTPUT" "$GODOT" --path "$ROOT" --windowed --resolution 1600x900 \
	--rendering-method gl_compatibility -- --new-game --capture-machine-set
python3 "$ROOT/tools/make_machine_montage.py" "$OUTPUT"
