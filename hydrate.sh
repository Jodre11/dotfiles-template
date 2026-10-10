#!/usr/bin/env bash
# hydrate.sh — Generate config files from .tmpl templates using config.env values.
# Run this before `stow`. Idempotent: safe to re-run.
#
# Usage:
#   ./hydrate.sh          # write every output, reporting NEW, CHANGED or UNCHANGED
#   ./hydrate.sh --diff   # preview: print each changed output's diff, write nothing
set -euo pipefail
# bash >= 5.2 expands & in a ${var//pattern/replacement} replacement to the match; keep config.env values literal.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
MODE="write"
HY_TMP=""

# remove_temp: delete the temp file an interrupted or failed write_output left behind.
remove_temp() {
    if [[ -n "$HY_TMP" ]]; then
        rm -f -- "$HY_TMP"
    fi
}
trap remove_temp EXIT
trap 'exit 1' HUP INT TERM

for arg in "$@"; do
    case "$arg" in
        --diff) MODE="diff" ;;
        *)      echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config.env not found. Copy config.env.example to config.env and fill in your values."
    exit 1
fi

# Source config.env
# shellcheck source=/dev/null
source "$CONFIG_FILE"

echo "Hydrating templates from config.env..."

# require_regular <output>: exit 1 with a FAIL line when <output> exists but is not a regular file (a symlink or a
# directory), which the write would replace or write into.
require_regular() {
    if [[ -L "$1" || ( -e "$1" && ! -f "$1" ) ]]; then
        echo "  FAIL $1 (not a regular file; hydrate.sh only replaces regular files)" >&2
        exit 1
    fi
}

# write_output <output> <content>: write <content> to a temp file beside <output>, then move it over <output>, so a
# failed write leaves <output> as it was. The temp starts as a copy of <output>, or of <output>.tmpl for a new output,
# so the result keeps that file's mode: scripts/datadog-mcp.sh, which is launched directly, stays executable. On any
# failure print FAIL and exit 1; the EXIT trap removes the temp.
write_output() {
    local output="$1" content="$2" mode_src="$1"
    if ! HY_TMP=$(mktemp "$(dirname -- "$output")/.$(basename -- "$output").hydrate.XXXXXX"); then
        HY_TMP=""
        echo "  FAIL $output (cannot create a temp file beside it)" >&2
        exit 1
    fi
    if [[ ! -f "$mode_src" ]]; then
        mode_src="$output.tmpl"
    fi
    if [[ -f "$mode_src" ]] && ! cp -p -- "$mode_src" "$HY_TMP"; then
        echo "  FAIL $output (cannot copy the mode of $mode_src; the file is unchanged)" >&2
        exit 1
    fi
    if ! printf '%s\n' "$content" >"$HY_TMP" || ! mv -f -- "$HY_TMP" "$output"; then
        echo "  FAIL $output (the write failed; the file is unchanged)" >&2
        exit 1
    fi
    HY_TMP=""
}

# preview_and_write <output> <new-content>: report NEW, CHANGED or UNCHANGED against the current file's bytes.
# In --diff mode print the unified diff and write nothing. A failed write prints FAIL and exits 1. Returns 0 if
# written, 1 if not.
preview_and_write() {
    local output="$1"
    local new_content="$2"

    require_regular "$output"
    if [[ -f "$output" ]]; then
        if cmp -s "$output" <(printf '%s\n' "$new_content"); then
            echo "  UNCHANGED $output"
            return 1
        fi
        echo "  CHANGED $output"
    else
        echo "  NEW $output"
    fi

    if [[ "$MODE" == "diff" ]]; then
        local current=/dev/null
        if [[ -f "$output" ]]; then
            current="$output"
        fi
        diff --color=auto -u --label "$output" --label "$output (hydrated)" \
            "$current" <(printf '%s\n' "$new_content") || true
        return 1
    fi

    write_output "$output" "$new_content"
    echo "  OK $output"
    return 0
}

# --- Helper: simple token replacement ---
hydrate_simple() {
    local tmpl="$1"
    local output="${tmpl%.tmpl}"

    if [[ ! -f "$tmpl" ]]; then
        echo "  SKIP $tmpl (not found)"
        return
    fi

    local content
    content=$(cat "$tmpl")

    # git
    content="${content//__GIT_USER_NAME__/${GIT_USER_NAME:-}}"
    content="${content//__GIT_USER_EMAIL__/${GIT_USER_EMAIL:-}}"
    content="${content//__GIT_SIGNING_KEY__/${GIT_SIGNING_KEY:-}}"

    # ssh / zsh
    content="${content//__SSH_AGENT_SOCK__/${SSH_AGENT_SOCK:-}}"
    content="${content//__NUGET_NAMESPACE__/${NUGET_NAMESPACE:-}}"
    content="${content//__JETBRAINS_TOOLBOX_PATH__/${JETBRAINS_TOOLBOX_PATH:-}}"

    # mcp / datadog
    content="${content//__DATADOG_MCP_SCRIPT__/${DATADOG_MCP_SCRIPT:-}}"
    content="${content//__DATADOG_SITE__/${DATADOG_SITE:-}}"

    # bedrock
    content="${content//__BEDROCK_REGION__/${BEDROCK_REGION:-}}"
    content="${content//__BEDROCK_AWS_PROFILE__/${BEDROCK_AWS_PROFILE:-}}"
    content="${content//__BEDROCK_DEFAULT_MODEL_ARN__/${BEDROCK_DEFAULT_MODEL_ARN:-}}"
    content="${content//__BEDROCK_HAIKU_ARN__/${BEDROCK_HAIKU_ARN:-}}"
    content="${content//__BEDROCK_SONNET_ARN__/${BEDROCK_SONNET_ARN:-}}"
    content="${content//__BEDROCK_OPUS_ARN__/${BEDROCK_OPUS_ARN:-}}"
    content="${content//__BEDROCK_OPUS_FALLBACK_ARNS__/${BEDROCK_OPUS_FALLBACK_ARNS:-}}"

    # aws
    content="${content//__SSO_START_URL__/${SSO_START_URL:-}}"
    content="${content//__SSO_REGION__/${SSO_REGION:-}}"
    content="${content//__AWS_REGION__/${AWS_REGION:-}}"

    # bitwarden
    content="${content//__BW_BIN__/${BW_BIN:-}}"

    preview_and_write "$output" "$content" || true
}

# --- AWS config: dynamic profile generation ---
hydrate_aws_config() {
    local tmpl="$SCRIPT_DIR/aws/.aws/config.tmpl"
    local output="$SCRIPT_DIR/aws/.aws/config"

    if [[ ! -f "$tmpl" ]]; then
        echo "  SKIP $tmpl (not found)"
        return
    fi

    # Start with the SSO session block from the template
    local content
    content=$(cat "$tmpl")
    content="${content//__SSO_START_URL__/${SSO_START_URL:-}}"
    content="${content//__SSO_REGION__/${SSO_REGION:-}}"
    content="${content//__SSO_SESSION_NAME__/${SSO_SESSION_NAME:-sso}}"

    # Append profiles from AWS_PROFILES array.
    # Region is optional — leave the field empty (e.g. `name|123|Role|`) to
    # omit the `region = ...` line for that profile.
    if [[ ${#AWS_PROFILES[@]} -gt 0 ]]; then
        content="$content"$'\n'
        for entry in "${AWS_PROFILES[@]}"; do
            IFS='|' read -r name account role region <<< "$entry"
            content="$content"$'\n'"[profile $name]"
            content="$content"$'\n'"sso_session = ${SSO_SESSION_NAME:-sso}"
            content="$content"$'\n'"sso_account_id = $account"
            content="$content"$'\n'"sso_role_name = $role"
            if [[ -n "$region" ]]; then
                content="$content"$'\n'"region = $region"
            fi
            content="$content"$'\n'
        done
    fi

    preview_and_write "$output" "$content" || true
}

# --- Hydrate all templates ---
hydrate_aws_config
hydrate_simple "$SCRIPT_DIR/docker/.docker/config.json.tmpl"
hydrate_simple "$SCRIPT_DIR/git/.gitconfig.tmpl"
hydrate_simple "$SCRIPT_DIR/mcp/.mcp.json.tmpl"
hydrate_simple "$SCRIPT_DIR/scripts/datadog-mcp.sh.tmpl"
hydrate_simple "$SCRIPT_DIR/ssh/.ssh/config.tmpl"
hydrate_simple "$SCRIPT_DIR/zsh/.claudeenv.tmpl"
hydrate_simple "$SCRIPT_DIR/zsh/.zprofile.tmpl"
hydrate_simple "$SCRIPT_DIR/zsh/.zshrc.tmpl"
if [[ -n "${BW_BIN:-}" ]]; then
    hydrate_simple "$SCRIPT_DIR/bitwarden/Library/LaunchAgents/com.user.bw-serve.plist.tmpl"
else
    echo "  SKIP bw-serve plist (BW_BIN unset)"
fi

echo ""
if [[ "$MODE" == "diff" ]]; then
    echo "Preview only — no files were written. Run without --diff to write."
else
    echo "Done. Run 'stow' to symlink packages into ~."
fi
