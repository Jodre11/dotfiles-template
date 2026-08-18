#!/usr/bin/env bash
# hydrate.sh — Generate config files from .tmpl templates using config.env values.
# Run this before `stow`. Idempotent: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config.env not found. Copy config.env.example to config.env and fill in your values."
    exit 1
fi

# Source config.env
# shellcheck source=/dev/null
source "$CONFIG_FILE"

echo "Hydrating templates from config.env..."

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

    printf '%s\n' "$content" > "$output"
    echo "  OK $tmpl → $output"
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

    printf '%s\n' "$content" > "$output"
    echo "  OK $tmpl → $output (${#AWS_PROFILES[@]} profiles)"
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
echo "Done. Run 'stow' to symlink packages into ~."
