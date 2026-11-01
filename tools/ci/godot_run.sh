#!/usr/bin/env bash
# Runs Godot headless on this project and fails if Godot reports any script or
# resource error. Godot itself still exits with 0 on most of those, so the
# output is checked too.
#   tools/ci/godot_run.sh --import
#   tools/ci/godot_run.sh --fixed-fps 60 -s res://tests/test_week.gd
# Set GODOT to the Godot executable (default: ~/godot/godot).
set -uo pipefail

GODOT="${GODOT:-$HOME/godot/godot}"
log="$(mktemp)"

timeout 300 "$GODOT" --headless --path . "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# Messages Godot prints when a script quits the engine; not real problems.
noise='Unreferenced static string|RID allocations of type|Pages in use exist at exit|ObjectDB instances leaked|resources still in use at exit|Thread object is being destroyed|wait_to_finish'

if grep -E 'SCRIPT ERROR|ERROR:|Parse Error|Failed to load' "$log" | grep -vE "$noise" | grep -q .; then
	echo "::error::Godot reported errors (see the log above)"
	exit 1
fi
if [ "$status" -eq 124 ]; then
	echo "::error::Godot did not finish within 5 minutes"
	exit 1
fi
if [ "$status" -ne 0 ]; then
	echo "::error::Godot exited with code $status"
	exit "$status"
fi
