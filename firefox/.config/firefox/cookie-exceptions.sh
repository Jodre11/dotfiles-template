#!/usr/bin/env bash
# cookie-exceptions.sh — seed persistent cookie exceptions into Firefox
#
# Inserts cookie ALLOW permissions into permissions.sqlite so that cookies
# for specified sites survive the clear-on-shutdown policy.
# Requires Firefox to be closed (permissions.sqlite is locked while running).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Sites to persist cookies for. Each entry is a full origin (scheme + host).
# Firefox has no wildcard support in moz_perms — subdomains need separate
# entries (e.g. github.com and gist.github.com both listed below).
COOKIE_ORIGINS=(
    # Accounts / SSO
    "https://accounts.google.com"
    "https://signin.aws.amazon.com"
    "https://vault.bitwarden.com"

    # Dev / reference
    "https://github.com"
    "https://gist.github.com"
    "https://stackoverflow.com"
    "https://claude.ai"

    # Cloud consoles
    "https://console.aws.amazon.com"
    "https://portal.azure.com"
    "https://console.cloud.google.com"

    # Comms / collab
    "https://teams.microsoft.com"
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

# Validate every origin starts with http:// or https:// before touching the DB
for origin in "${COOKIE_ORIGINS[@]}"; do
    if [[ ! "$origin" =~ ^https?:// ]]; then
        echo "Error: invalid origin '$origin' (must start with http:// or https://)" >&2
        exit 1
    fi
done

NOW_MS="$(date +%s)000"

# Build a single sqlite3 batch from the array (skip entries that already exist)
{
    echo "BEGIN TRANSACTION;"
    for origin in "${COOKIE_ORIGINS[@]}"; do
        cat <<SQL
INSERT INTO moz_perms (origin, type, permission, expireType, expireTime, modificationTime)
SELECT '$origin', 'cookie', 1, 0, 0, $NOW_MS
WHERE NOT EXISTS (SELECT 1 FROM moz_perms WHERE origin='$origin' AND type='cookie');
SQL
    done
    echo "COMMIT;"
} | sqlite3 "$PERMS_DB"

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
