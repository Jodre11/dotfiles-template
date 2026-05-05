#!/usr/bin/env bash
# Verifies that .gitleaks.toml rules and .githooks/pre-commit patterns stay in sync.
# Run in CI or locally: bash tests/test-pattern-sync.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITLEAKS="$REPO_ROOT/.gitleaks.toml"
PRECOMMIT="$REPO_ROOT/.githooks/pre-commit"

ERRORS=0

# --- Check 1: Every gitleaks regex has a corresponding pre-commit pattern ---

echo "Checking gitleaks rules have matching pre-commit patterns..."

# Extract rule IDs and their regexes from .gitleaks.toml
while IFS= read -r line; do
    if [[ "$line" =~ ^id\ =\ \"(.+)\" ]]; then
        current_id="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ ^regex\ =\ \'\'\'(.+)\'\'\' ]]; then
        regex="${BASH_REMATCH[1]}"
        # Check that at least part of the regex concept appears in the pre-commit hook.
        # We extract a representative literal or structural fragment to search for.
        case "$current_id" in
            org-aws-account-id)
                # Pre-commit splits this into multiple patterns; check for the ARN one
                if ! grep -q 'arn:aws' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — no ARN pattern in pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-sso-url)
                if ! grep -q 'awsapps' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-ecr-registry)
                if ! grep -qF 'dkr' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-bedrock-arn-fragment)
                if ! grep -q 'application-inference-profile' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-ad-path)
                if ! grep -q 'DC=' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-name)
                if ! grep -q 'yourorg' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            org-internal-project)
                if ! grep -q 'internal-project' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            personal-identity)
                if ! grep -q 'YourGitHubUser' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
            ssh-private-key)
                if ! grep -q 'PRIVATE KEY' "$PRECOMMIT"; then
                    echo "  FAIL: $current_id — missing from pre-commit"
                    ((ERRORS++))
                fi
                ;;
        esac
    fi
done < "$GITLEAKS"

# --- Check 2: Pre-commit patterns must not use PCRE-only syntax ---

echo "Checking pre-commit patterns use ERE-compatible syntax..."

# Extract patterns from the PATTERNS array
in_array=0
while IFS= read -r line; do
    if [[ "$line" =~ ^PATTERNS=\( ]]; then
        in_array=1
        continue
    fi
    if [[ $in_array -eq 1 && "$line" =~ ^\) ]]; then
        break
    fi
    if [[ $in_array -eq 1 ]]; then
        # Skip comments and blank lines
        stripped="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$stripped" || "$stripped" == \#* ]] && continue
        # Check for common PCRE-only constructs
        if [[ "$stripped" =~ \\s|\\d|\\w|\\b|\(\?: ]]; then
            echo "  FAIL: PCRE syntax in pre-commit pattern: $stripped"
            ((ERRORS++))
        fi
    fi
done < "$PRECOMMIT"

# --- Check 3: Gitleaks allowlist includes self-referencing files ---

echo "Checking gitleaks allowlist includes guard files..."

for required in ".githooks/pre-commit" ".gitleaks.toml"; do
    if ! grep -q "$required" "$GITLEAKS"; then
        echo "  FAIL: $required missing from gitleaks allowlist"
        ((ERRORS++))
    fi
done

# --- Result ---

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "FAILED: $ERRORS error(s) found"
    exit 1
fi

echo "PASSED: all pattern sync checks OK"
