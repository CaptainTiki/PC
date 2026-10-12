#!/bin/bash
# Run Godot from the project root. Headless for tool scripts; use render.sh for screenshots.
exec /home/claude/tools/godot --headless --audio-driver Dummy --path /home/claude/collider "$@"
