#!/usr/bin/env bash
# setup.sh — apply arkenfox + user-overrides to the Firefox profile
#
# 1. Detects the default-release profile
# 2. Requires Firefox to be closed
# 3. Backs up bookmarks
# 4. Downloads arkenfox updater.sh and prefsCleaner.sh
# 5. Runs updater with user-overrides.js appended
# 6. Runs prefsCleaner to remove stale manual prefs
# 7. Seeds cookie exceptions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Pin to a specific arkenfox release — update after verifying compatibility
ARKENFOX_VERSION="140.1"
ARKENFOX_REPO="https://raw.githubusercontent.com/arkenfox/user.js/$ARKENFOX_VERSION"

# --- Pre-flight checks --------------------------------------------------------

PROFILE_DIR="$(find_profile)"
echo "Profile: $PROFILE_DIR"

if pgrep -xi "firefox" > /dev/null 2>&1; then
    echo "Error: Firefox is running. Close it and try again." >&2
    exit 1
fi

# --- Backup bookmarks ---------------------------------------------------------

echo ""
echo "==> Backing up bookmarks..."
"$SCRIPT_DIR/backup-bookmarks.sh" "$PROFILE_DIR"

# --- Download arkenfox scripts ------------------------------------------------

echo ""
echo "==> Downloading arkenfox scripts..."

for script in updater.sh prefsCleaner.sh; do
    curl -fsSL "$ARKENFOX_REPO/$script" -o "$PROFILE_DIR/$script"
    chmod +x "$PROFILE_DIR/$script"
    echo "Downloaded $script"
done

# --- Run arkenfox updater -----------------------------------------------------

echo ""
echo "==> Running arkenfox updater..."
# -o: append user-overrides.js from our Stow-managed path
# -s: silent (non-interactive)
# -b: keep only the most recent backup
(cd "$PROFILE_DIR" && ./updater.sh -o "$SCRIPT_DIR/user-overrides.js" -s -b)

# --- Run prefsCleaner ---------------------------------------------------------

echo ""
echo "==> Running prefsCleaner (removing stale manual prefs)..."
# -s: silent (non-interactive)
(cd "$PROFILE_DIR" && ./prefsCleaner.sh -s)

# --- Seed cookie exceptions ---------------------------------------------------

echo ""
if [[ ! -f "$PROFILE_DIR/permissions.sqlite" ]]; then
    echo "Warning: permissions.sqlite not found — skipping cookie exception seeding." >&2
    echo "Launch Firefox once to create the database, then re-run setup.sh." >&2
else
    echo "==> Seeding cookie exceptions..."
    "$SCRIPT_DIR/cookie-exceptions.sh" "$PROFILE_DIR"
fi

# --- Done ---------------------------------------------------------------------

echo ""
echo "Setup complete. Start Firefox and verify:"
echo "  1. about:config — network.dns.disableIPv6 should not be set"
echo "  2. about:config — privacy.resistFingerprinting should not be set"
echo "  3. about:config — privacy.fingerprintingProtection should be true"
echo "  4. about:config — browser.contentblocking.category should be strict"
echo "  5. Test localhost OAuth (claude personal auth)"
echo "  6. Test claude.ai loads correctly"
echo "  7. Remove the Granted extension (about:addons)"
