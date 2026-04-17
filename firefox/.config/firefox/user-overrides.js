// user-overrides.js — appended to arkenfox user.js by updater.sh
//
// These overrides diverge from arkenfox defaults for usability.
// Everything else (telemetry, HTTPS-only, ETP Strict, FPP, referrer
// trimming, cookie clearing on shutdown, etc.) uses arkenfox defaults.

// --- Usability ---------------------------------------------------------------

// Restore tabs after crash (arkenfox disables via sessionstore.privacy_level=2
// and resume_from_crash=false; low privacy cost, high usability)
user_pref("browser.sessionstore.resume_from_crash", true);

// --- Credentials & autofill -------------------------------------------------

// Disable the built-in password manager entirely — Bitwarden handles this.
// Arkenfox disables autofill and formless capture but still lets Firefox
// prompt to save passwords. These prefs are in arkenfox section 5000 (opt-in).
user_pref("signon.rememberSignons", false);            // [5003] never ask to save passwords
user_pref("extensions.formautofill.addresses.enabled", false);  // [5005] no address autofill
user_pref("extensions.formautofill.creditCards.enabled", false); // [5005] no credit card autofill

// --- Notes -------------------------------------------------------------------
//
// Arkenfox defaults already cover dev needs:
//   - IPv6 enabled (no disableIPv6 pref)
//   - WebRTC enabled, ICE restricted to default address only
//   - XOriginPolicy at 0 (referrers sent cross-origin, trimmed to origin)
//   - Localhost permanently exempt from HTTPS-only mode
//   - FPP active via ETP Strict (not RFP)
