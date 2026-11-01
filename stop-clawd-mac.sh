#!/bin/bash
set -euo pipefail

RUNNING_PIDS=$(pgrep -x "ClawdPet" || true)

if [ -n "$RUNNING_PIDS" ]; then
    echo "Stopping Clawd Pet (PID: $RUNNING_PIDS)..."
    kill $RUNNING_PIDS
    sleep 0.5
    echo "👋 Clawd Pet stopped."
else
    echo "Clawd Pet is not running."
fi
