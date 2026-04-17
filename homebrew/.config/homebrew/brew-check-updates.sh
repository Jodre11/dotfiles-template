#!/usr/bin/env bash
# brew-check-updates.sh — check for outdated Homebrew packages and notify
#
# Checks formulae and casks (including auto-updating/greedy casks).
# Sends a macOS notification with the count and package names.
# Run via launchd daily or on demand.
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

# Update the index first
brew update --quiet 2>/dev/null

# Check outdated formulae and greedy casks
outdated=$(brew outdated --greedy-latest 2>/dev/null)

if [ -z "$outdated" ]; then
    exit 0
fi

count=$(echo "$outdated" | wc -l | tr -d ' ')
names=$(echo "$outdated" | paste -sd ',' - | sed 's/,/, /g')

# Truncate long lists for the notification subtitle
if [ ${#names} -gt 120 ]; then
    names="${names:0:117}..."
fi

osascript -e "display notification \"$names\" with title \"Homebrew: $count update(s) available\" subtitle \"Run: bup\""
