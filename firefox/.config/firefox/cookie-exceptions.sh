#!/usr/bin/env bash
# cookie-exceptions.sh — seed persistent cookie exceptions into Firefox
#
# Inserts cookie ALLOW permissions into permissions.sqlite so that cookies
# for specified sites survive the clear-on-shutdown policy.
# Requires Firefox to be closed (permissions.sqlite is locked while running).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Sites to persist cookies for (origins must include scheme)
COOKIE_ORIGINS=(
    "https://github.com"
    "https://claude.ai"
    "https://accounts.google.com"
    "https://signin.aws.amazon.com"
    "https://vault.bitwarden.com"
)

# --- Main ---------------------------------------------------------------------

# Accept profile dir as $1 (when called from setup.sh) or discover it
PROFILE_DIR="${1:-$(find_profile)}"
PERMS_DB="$PROFILE_DIR/permissions.sqlite"

if [[ ! -f "$PERMS_DB" ]]; then
    echo "Error: permissions.sqlite not found at $PERMS_DB" >&2
    exit 1
fi

if pgrep -xi "firefox" > /dev/null 2>&1; then
    echo "Error: Firefox is running. Close it before seeding cookie exceptions." >&2
    exit 1
fi

NOW_MS="$(date +%s)000"

# Batch all inserts into a single sqlite3 session (skip existing entries)
sqlite3 "$PERMS_DB" <<SQL
INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT 'https://github.com', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='https://github.com' AND type='cookie');

INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT 'https://claude.ai', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='https://claude.ai' AND type='cookie');

INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT 'https://accounts.google.com', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='https://accounts.google.com' AND type='cookie');

INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT 'https://signin.aws.amazon.com', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='https://signin.aws.amazon.com' AND type='cookie');

INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT 'https://vault.bitwarden.com', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='https://vault.bitwarden.com' AND type='cookie');
SQL

# Report results per origin
for origin in "${COOKIE_ORIGINS[@]}"; do
    existing=$(sqlite3 "$PERMS_DB" \
        "SELECT COUNT(*) FROM moz_perms WHERE origin='$origin' AND type='cookie';")
    if [[ "$existing" -gt 0 ]]; then
        echo "Cookie exception present: $origin"
    else
        echo "Warning: cookie exception missing: $origin" >&2
    fi
done
