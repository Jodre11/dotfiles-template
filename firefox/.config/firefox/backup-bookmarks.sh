#!/usr/bin/env bash
# backup-bookmarks.sh — back up Firefox bookmarks (places.sqlite)
#
# Copies places.sqlite from the default-release profile to
# ~/.config/firefox/backups/. Keeps the 5 most recent backups.
# Requires Firefox to be closed (places.sqlite is locked while running).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

BACKUP_DIR="$HOME/.config/firefox/backups"

# --- Main ---------------------------------------------------------------------

# Accept profile dir as $1 (when called from setup.sh) or discover it
PROFILE_DIR="${1:-$(find_profile)}"
PLACES_DB="$PROFILE_DIR/places.sqlite"

if [[ ! -f "$PLACES_DB" ]]; then
    echo "Error: places.sqlite not found at $PLACES_DB" >&2
    exit 1
fi

# Check Firefox is not running (places.sqlite is locked while running)
if pgrep -xi "firefox" > /dev/null 2>&1; then
    echo "Error: Firefox is running. Close it before backing up bookmarks." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y-%m-%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/bookmarks-$TIMESTAMP.sqlite"

cp "$PLACES_DB" "$BACKUP_FILE"
echo "Bookmarks backed up to $BACKUP_FILE"

# Keep only the 5 most recent backups (filenames sort chronologically)
ls "$BACKUP_DIR"/bookmarks-*.sqlite 2>/dev/null | sort -r | tail -n +6 | while read -r old; do
    rm -f "$old"
    echo "Removed old backup: $(basename "$old")"
done
