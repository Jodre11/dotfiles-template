#!/usr/bin/env bash
# setup-chrome.sh — harden Chrome for development/Playwright use
#
# Applies enterprise policies via `defaults write` (recommended level).
# Chrome is used solely as a dev/testing browser; these settings disable
# Google account integration, telemetry, and unnecessary network calls.
#
# Idempotent — safe to re-run after Chrome updates.
# Verify at chrome://policy after restarting Chrome.
set -euo pipefail

DOMAIN="com.google.Chrome"

echo "Applying Chrome hardening policies..."

# --- Sign-in & sync ------------------------------------------------------
# 0 = sign-in disabled entirely
defaults write "$DOMAIN" BrowserSignin -int 0
defaults write "$DOMAIN" SyncDisabled -bool true

# --- Telemetry & reporting ------------------------------------------------
defaults write "$DOMAIN" MetricsReportingEnabled -bool false
defaults write "$DOMAIN" UrlKeyedAnonymizedDataCollectionEnabled -bool false
defaults write "$DOMAIN" SafeBrowsingProtectionLevel -int 1

# --- Network chatter ------------------------------------------------------
# 2 = never preconnect or prefetch
defaults write "$DOMAIN" NetworkPredictionOptions -int 2
defaults write "$DOMAIN" SearchSuggestEnabled -bool false
defaults write "$DOMAIN" AlternateErrorPagesEnabled -bool false
defaults write "$DOMAIN" TranslateEnabled -bool false
defaults write "$DOMAIN" SpellCheckServiceEnabled -bool false

# --- Autofill & password manager ------------------------------------------
defaults write "$DOMAIN" AutofillAddressEnabled -bool false
defaults write "$DOMAIN" AutofillCreditCardEnabled -bool false
defaults write "$DOMAIN" PasswordManagerEnabled -bool false

# --- Background & promotional bloat ---------------------------------------
defaults write "$DOMAIN" BackgroundModeEnabled -bool false
defaults write "$DOMAIN" PromotionalTabsEnabled -bool false

# --- Force-install extensions ---------------------------------------------
# Format: <extension_id>;<update_url>
# These are auto-installed on first launch and cannot be removed by the user.
CWS_UPDATE="https://clients2.google.com/service/update2/crx"
defaults write "$DOMAIN" ExtensionInstallForcelist -array \
    "nngceckbapebfimnlniiiahkandclblb;$CWS_UPDATE" \
    "mmlmfjhmonkocbjadbfplnigmagldckm;$CWS_UPDATE"

# --- Block unwanted built-in extensions -----------------------------------
# Google Docs Offline — not needed on a dev browser, phones home to Google
defaults write "$DOMAIN" ExtensionInstallBlocklist -array \
    "ghbmnnjooekpmoecnnnilnnbdlolhkhi"

echo "Done. Restart Chrome and verify at chrome://policy"
