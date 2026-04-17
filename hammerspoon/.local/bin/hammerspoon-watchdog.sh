#!/bin/bash
# Hammerspoon watchdog — kills and restarts Hammerspoon if it stops responding.
# Designed to recover from event tap deadlocks that lock out keyboard input.
# Runs via launchd every 30 seconds.

set -euo pipefail

LOG_FILE="$HOME/.local/share/dictation/watchdog.log"
TIMEOUT_SECONDS=5

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOG_FILE"
}

# Exit silently if Hammerspoon is not running
if ! pgrep -q Hammerspoon; then
    exit 0
fi

# Health check: ask Hammerspoon to evaluate a trivial expression
# Use a background process with kill since macOS lacks GNU timeout
hs -c "true" > /dev/null 2>&1 &
HS_PID=$!
TIMED_OUT=false
for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
    if ! kill -0 "$HS_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done
if kill -0 "$HS_PID" 2>/dev/null; then
    kill "$HS_PID" 2>/dev/null || true
    TIMED_OUT=true
fi
wait "$HS_PID" 2>/dev/null || true
if [ "$TIMED_OUT" = false ]; then
    exit 0
fi

# Hammerspoon is stuck
log "WATCHDOG: Hammerspoon unresponsive, killing"
killall -9 Hammerspoon 2>/dev/null || true
sleep 2
open -a Hammerspoon
log "WATCHDOG: Hammerspoon restarted"
