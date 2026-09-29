#!/usr/bin/env bash
# Tests for hydrate.sh. Each case runs a scratch copy of hydrate.sh beside fixture templates and a fixture config.env,
# so this repo's outputs and its config.env are never read or written.
# Run: bash tests/test-hydrate.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0
rc=0
out=""

# check <description> <expected> <actual>: record PASS when <actual> equals <expected>.
check() {
    if [[ "$3" == "$2" ]]; then
        passes=$((passes + 1))
        echo "PASS $1"
    else
        failures=$((failures + 1))
        echo "FAIL $1 (expected '$2', got '$3')"
    fi
}

# check_match <description> <regex> <actual>: record PASS when <actual> matches <regex>.
check_match() {
    if [[ "$3" =~ $2 ]]; then
        passes=$((passes + 1))
        echo "PASS $1"
    else
        failures=$((failures + 1))
        echo "FAIL $1 (no match for '$2')"
    fi
}

# check_no_match <description> <regex> <actual>: record PASS when <actual> does not match <regex>.
check_no_match() {
    if [[ ! "$3" =~ $2 ]]; then
        passes=$((passes + 1))
        echo "PASS $1"
    else
        failures=$((failures + 1))
        echo "FAIL $1 (unexpected match for '$2')"
    fi
}

# check_same <description> <file> <copy>: record PASS when <file> is byte-identical to <copy>.
check_same() {
    if cmp -s "$2" "$3"; then
        passes=$((passes + 1))
        echo "PASS $1"
    else
        failures=$((failures + 1))
        echo "FAIL $1 ($2 changed)"
    fi
}

# new_fixture: create a scratch dir holding a copy of hydrate.sh, a fixture config.env with one AWS profile, and
# templates for .zshrc, .gitconfig, datadog-mcp.sh and the AWS config; print its path. The account ID is built at
# run time, so this file carries no literal the git guards flag.
new_fixture() {
    local d acct
    d=$(mktemp -d "$tmp/fx.XXXXXX")
    mkdir -p "$d/zsh" "$d/git" "$d/scripts" "$d/aws/.aws"
    cp "$repo_root/hydrate.sh" "$d/hydrate.sh"
    acct=$(printf '%012d' 42)
    printf '%s\n' 'GIT_USER_NAME="Fixture User"' 'DATADOG_SITE="datadoghq.example"' \
        'SSO_START_URL="https://sso.example.invalid/start"' 'SSO_REGION="eu-west-1"' \
        "AWS_PROFILES=(\"dev|$acct|Dev|eu-west-1\")" >"$d/config.env"
    printf '%s\n' 'name=__GIT_USER_NAME__' >"$d/zsh/.zshrc.tmpl"
    printf '%s\n' 'user=__GIT_USER_NAME__' >"$d/git/.gitconfig.tmpl"
    printf '%s\n' '#!/usr/bin/env bash' 'site=__DATADOG_SITE__' >"$d/scripts/datadog-mcp.sh.tmpl"
    printf '%s\n' '[sso-session __SSO_SESSION_NAME__]' 'sso_start_url = __SSO_START_URL__' \
        'sso_region = __SSO_REGION__' >"$d/aws/.aws/config.tmpl"
    printf '%s\n' "$d"
}

# run_hydrate <dir> <flag>: run <dir>'s hydrate.sh with <flag>, or with no argument when <flag> is empty; set rc and
# out.
run_hydrate() {
    rc=0
    if [[ -n "$2" ]]; then
        out=$(bash "$1/hydrate.sh" "$2" 2>&1) || rc=$?
    else
        out=$(bash "$1/hydrate.sh" 2>&1) || rc=$?
    fi
}

# run_hydrate_path <dir> <bin-dir>: run <dir>'s hydrate.sh with <bin-dir> first on PATH; set rc and out.
run_hydrate_path() {
    rc=0
    out=$(PATH="$2:$PATH" bash "$1/hydrate.sh" 2>&1) || rc=$?
}

# stub_failing <dir> <command>: write a stub <command> that always fails into <dir>/bin; print that directory.
stub_failing() {
    mkdir -p "$1/bin"
    printf '#!/bin/sh\nexit 1\n' >"$1/bin/$2"
    chmod +x "$1/bin/$2"
    printf '%s' "$1/bin"
}

# only_zshrc <dir>: drop every fixture template but .zshrc's, so a run writes that one output.
only_zshrc() {
    rm -f "$1/aws/.aws/config.tmpl" "$1/git/.gitconfig.tmpl" "$1/scripts/datadog-mcp.sh.tmpl"
}

# --- --diff previews every change and writes nothing
d=$(new_fixture)
printf '%s\n' 'name=stale' >"$d/zsh/.zshrc"
cp "$d/zsh/.zshrc" "$tmp/zshrc.before"
run_hydrate "$d" --diff
check "--diff exits 0" 0 "$rc"
check_same "--diff leaves an existing output untouched" "$d/zsh/.zshrc" "$tmp/zshrc.before"
if [[ -e "$d/git/.gitconfig" ]]; then
    check "--diff creates no new output" "absent" "present"
else
    check "--diff creates no new output" "absent" "absent"
fi
check_match "--diff reports CHANGED" "CHANGED $d/zsh/.zshrc" "$out"
check_match "--diff prints the hydrated line" '\+name=Fixture User' "$out"
check_match "--diff reports NEW" "NEW $d/git/.gitconfig" "$out"
check_match "--diff prints a new output's content" '\+user=Fixture User' "$out"
check_match "--diff says nothing was written" 'Preview only' "$out"

run_hydrate "$d" --bogus
check "an unknown flag exits 1" 1 "$rc"

# --- a bare run writes; a second run finds nothing to change
run_hydrate "$d" ""
check "a bare run exits 0" 0 "$rc"
check "a bare run writes the hydrated content" "name=Fixture User" "$(cat "$d/zsh/.zshrc")"
run_hydrate "$d" ""
check_match "a second run reports .zshrc UNCHANGED" "UNCHANGED $d/zsh/.zshrc" "$out"
check_match "a second run reports the AWS config UNCHANGED, though its content ends in a blank line" \
    "UNCHANGED $d/aws/.aws/config" "$out"
check_no_match "a second run writes nothing" '  OK ' "$out"

# --- the write is in place, so a launched script keeps its execute bit
d=$(new_fixture)
printf '%s\n' '#!/usr/bin/env bash' 'site=stale' >"$d/scripts/datadog-mcp.sh"
chmod 755 "$d/scripts/datadog-mcp.sh"
run_hydrate "$d" ""
check_match "a changed script is rewritten" "OK $d/scripts/datadog-mcp.sh" "$out"
if [[ -x "$d/scripts/datadog-mcp.sh" ]]; then
    check "a rewritten script stays executable" "yes" "yes"
else
    check "a rewritten script stays executable" "yes" "no"
fi

# --- a failed write stops the run
d=$(new_fixture)
mkdir "$d/zsh/.zshrc"
run_hydrate "$d" ""
check "a failed write exits 1" 1 "$rc"
check_match "a failed write prints FAIL" "FAIL $d/zsh/.zshrc" "$out"
check_no_match "a failed write prints no OK for that output" "OK $d/zsh/.zshrc" "$out"

# --- the write is atomic: a failure leaves the output as it was
d=$(new_fixture)
only_zshrc "$d"
printf '%s\n' 'name=stale' >"$d/zsh/.zshrc"
cp "$d/zsh/.zshrc" "$tmp/zshrc.before"
run_hydrate_path "$d" "$(stub_failing "$d/mv-fails" mv)"
check "a failed move exits 1" 1 "$rc"
check_match "a failed move prints FAIL" "FAIL $d/zsh/.zshrc" "$out"
check_same "a failed move leaves the output as it was" "$d/zsh/.zshrc" "$tmp/zshrc.before"
check "a failed move leaves no temp file behind" "" "$(find "$d/zsh" -name '..zshrc.*' -print)"
run_hydrate_path "$d" "$(stub_failing "$d/mktemp-fails" mktemp)"
check "a failed temp-file creation exits 1" 1 "$rc"
check_same "a failed temp-file creation leaves the output as it was" "$d/zsh/.zshrc" "$tmp/zshrc.before"

# --- a symlinked output is refused, by the preview too
d=$(new_fixture)
only_zshrc "$d"
printf '%s\n' 'name=real' >"$d/zsh/real"
cp "$d/zsh/real" "$tmp/real.before"
ln -s real "$d/zsh/.zshrc"
run_hydrate "$d" --diff
check "--diff on a symlinked output exits 1" 1 "$rc"
check_match "--diff refuses a symlinked output" "FAIL $d/zsh/.zshrc .*not a regular file" "$out"
run_hydrate "$d" ""
check "a write to a symlinked output exits 1" 1 "$rc"
if [[ -L "$d/zsh/.zshrc" ]]; then
    check "the symlink is left in place" "yes" "yes"
else
    check "the symlink is left in place" "yes" "no"
fi
check_same "the symlink's target is unchanged" "$d/zsh/real" "$tmp/real.before"

# --- a new output takes its template's mode, so a fresh clone's launched script is executable
d=$(new_fixture)
chmod 755 "$d/scripts/datadog-mcp.sh.tmpl"
run_hydrate "$d" ""
if [[ -x "$d/scripts/datadog-mcp.sh" ]]; then
    check "a new output from an executable template is executable" "yes" "yes"
else
    check "a new output from an executable template is executable" "yes" "no"
fi
if [[ -x "$d/git/.gitconfig" ]]; then
    check "a new output from a plain template is not executable" "no" "yes"
else
    check "a new output from a plain template is not executable" "no" "no"
fi

# --- summary
echo ""
echo "$((passes + failures)) checks: $passes passed, $failures failed"
if [[ $failures -gt 0 ]]; then
    exit 1
fi
