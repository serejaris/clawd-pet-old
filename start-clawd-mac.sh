#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BINARY="$SCRIPT_DIR/.build/release/ClawdPet"
if [ ! -f "$BINARY" ]; then
    # In some SPM versions, target path may include architecture
    BINARY=$(find "$SCRIPT_DIR/.build" -type f -name "ClawdPet" -perm +111 2>/dev/null | grep -E "release/ClawdPet$" | head -n 1 || true)
fi

# Build if binary is missing or if explicitly requested
if [ -z "$BINARY" ] || [ ! -f "$BINARY" ] || [ "${1:-}" = "--build" ]; then
    echo "🦀 Building Clawd Pet (release)..."
    swift build -c release
    BINARY="$SCRIPT_DIR/.build/release/ClawdPet"
fi

if [ ! -f "$BINARY" ]; then
    echo "❌ Error: Could not locate built ClawdPet binary."
    exit 1
fi

# Check if an instance is already running
RUNNING_PID=$(pgrep -x "ClawdPet" || true)
if [ -n "$RUNNING_PID" ]; then
    echo "⚠️ Clawd Pet is already running (PID: $RUNNING_PID). Restarting..."
    kill "$RUNNING_PID" 2>/dev/null || true
    sleep 0.5
fi

# Launch in background
LOG_FILE="/tmp/clawd-pet.log"
nohup "$BINARY" > "$LOG_FILE" 2>&1 &
NEW_PID=$!

sleep 0.5
if ps -p "$NEW_PID" > /dev/null; then
    echo "✅ Clawd Pet started successfully!"
    echo "   PID: $NEW_PID"
    echo "   Logs: $LOG_FILE"
    echo "   To stop: ./stop-clawd-mac.sh (or right-click Clawd -> Quit)"
else
    echo "❌ Clawd Pet failed to start. Log output:"
    cat "$LOG_FILE"
    exit 1
fi
