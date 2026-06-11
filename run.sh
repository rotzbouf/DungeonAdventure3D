#!/usr/bin/env bash
# Launches the game via the project-local Godot binary, forwarding all
# arguments to the game (see bootstrap/bootstrap.gd for recognized flags).
#
# Examples:
#   ./run.sh                          # client, connects to 127.0.0.1:7777
#   ./run.sh --host                   # listen host (server + local player)
#   ./run.sh --host --port=7778       # listen host on a custom port
#   ./run.sh --connect=127.0.0.1:7778 # client connecting to a custom address
#   ./run.sh --server                 # dedicated server (windowed; add --headless to hide it)

cd "$(dirname "$0")"
exec .tools/godot/godot4 --path . -- "$@"
