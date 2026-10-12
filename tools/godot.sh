#!/bin/bash
# Run Godot from the project root. Headless for tool scripts; use render.sh for screenshots.
exec ${GODOT:-/home/claude/tools/godot} --headless --audio-driver Dummy --path $(cd "$(dirname "$0")/.." && pwd) "$@"
