#!/usr/bin/env zsh
# shellcheck shell=bash
# bw-unlock.zsh — unlock the LaunchAgent-managed `bw serve` daemon once per boot.
# Sourced from .zshrc. Defines `bw-unlock` (manual) plus a lazy login hook.

: "${BW_SERVE_URL:=http://localhost:8087}"

# _bw_status — echo the daemon's vault status, or empty if unreachable.
# Parses {"data":{"template":{"status":"unlocked"}}} without requiring jq.
_bw_status() {
    local body
    body=$(curl -s --max-time 3 "$BW_SERVE_URL/status" 2>/dev/null) || return 1
    printf '%s' "$body" | grep -o '"status":"[^"]*"' | tail -1 | sed 's/.*:"//;s/"$//'
}

# _bw_json_escape — escape a string for a JSON string literal (in-memory only).
_bw_json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# _bw_unlock_post — POST {"password":...} to /unlock via stdin (never argv/disk).
_bw_unlock_post() {
    local escaped
    escaped=$(_bw_json_escape "$1")
    printf '{"password":"%s"}' "$escaped" | curl -s --max-time 10 \
        -H 'Content-Type: application/json' \
        --data-binary @- \
        "$BW_SERVE_URL/unlock"
}

# bw-unlock — ensure the vault is unlocked; prompt once if locked.
# Pass --hook for the lazy login path (dormant unless the LaunchAgent exists).
bw-unlock() {
    local from_hook=0
    [[ "$1" == "--hook" ]] && from_hook=1

    if (( from_hook )); then
        launchctl list com.user.bw-serve &>/dev/null || return 0
    fi

    # Note: `status` is a read-only special variable in zsh (alias for $?),
    # so this local must use a different name.
    local vault_status
    vault_status=$(_bw_status)

    if [[ -z "$vault_status" ]]; then
        (( from_hook )) && return 0
        print -u2 "bw serve not reachable at $BW_SERVE_URL — is the LaunchAgent loaded? Retry: bw-unlock"
        return 1
    fi

    case "$vault_status" in
        unlocked)
            (( from_hook )) || print "Bitwarden vault already unlocked."
            return 0
            ;;
        unauthenticated)
            print -u2 "Bitwarden CLI is logged out. Run: bw login   (then: bw-unlock)"
            return 1
            ;;
        locked) ;;
        *)
            print -u2 "Unexpected bw serve status: '$vault_status'. Retry: bw-unlock"
            return 1
            ;;
    esac

    [[ -o interactive ]] || return 0

    local pw
    if ! IFS= read -rs "pw?Unlock Bitwarden vault (master password): "; then
        print
        return 1
    fi
    print

    if [[ -z "$pw" ]]; then
        print "No password entered; vault stays locked. Retry: bw-unlock"
        return 1
    fi

    local resp
    resp=$(_bw_unlock_post "$pw")
    unset pw

    if printf '%s' "$resp" | grep -q '"success":true'; then
        print "Bitwarden vault unlocked."
        return 0
    fi

    print -u2 "Unlock failed: invalid master password."
    print -u2 "  To retry: run  bw-unlock"
    print -u2 "  (the vault stays locked until a successful unlock)"
    return 1
}

if [[ -o interactive ]]; then
    bw-unlock --hook
fi
