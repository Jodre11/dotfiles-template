#!/usr/bin/env bash
# Tests for the claude() and claude-personal() wrappers in zsh/.zshrc.tmpl. Each case extracts the functions, runs a
# wrapper under `zsh -f` with stub tmux, claude and slug scripts on PATH and a scratch HOME, and checks whether claude
# ran in a tmux pane (given as one string: tmux runs several arguments directly, without a shell) or directly, which
# arguments claude received and whether claude-personal stripped the Bedrock environment.
# Run: bash tests/test-claude-wrapper.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0

# check <description> <expected> <actual>: record PASS when <actual> equals <expected>.
check() {
    if [[ "$3" == "$2" ]]; then
        passes=$((passes + 1))
        echo "PASS $1"
    else
        failures=$((failures + 1))
        printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"
    fi
}

if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP all (zsh not installed)"
    exit 0
fi

mkdir -p "$tmp/bin" "$tmp/home/.claude/scripts" "$tmp/out"

cat > "$tmp/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 1 ;;
    new-session)
        shift 3
        printf '%s' "$#" > "$WRAPPER_TEST_OUT/tmux-argc"
        exec zsh -f -c "$1"
        ;;
esac
exit 0
EOF

cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WRAPPER_TEST_OUT/claude-argv"
printf '%s' "${CLAUDE_CODE_USE_BEDROCK-<unset>}" > "$WRAPPER_TEST_OUT/claude-bedrock"
EOF

printf '#!/usr/bin/env bash\necho c-test-0000\n' > "$tmp/home/.claude/scripts/derive-claude-slug.sh"
chmod +x "$tmp/bin/tmux" "$tmp/bin/claude" "$tmp/home/.claude/scripts/derive-claude-slug.sh"

awk '/^claude-arg-mode\(\) \{$/,/^}$/; /^claude\(\) \{$/,/^}$/; /^claude-personal\(\) \{$/,/^}$/' \
    "$repo_root/zsh/.zshrc.tmpl" > "$tmp/wrappers.zsh"

# Claude Code's shell snapshot drops functions whose names start with _, so a wrapper calling one fails in the ! and
# Bash-tool shells.
check "the wrappers call no _-prefixed function" "" \
    "$(grep -oE '^[[:space:]]+_[[:alnum:]_-]+' "$tmp/wrappers.zsh" | tr -d '[:space:]' || true)"
check "the argument classifier is extracted" "1" "$(grep -c '^claude-arg-mode() {$' "$tmp/wrappers.zsh" || true)"

# run_wrapper <fallback> <function> [arg...]: run the wrapper with BEDROCK_OPUS_FALLBACK_ARNS=<fallback> both in its
# environment and in the scratch ~/.claudeenv; leave tmux's argument count, claude's argv and claude's
# CLAUDE_CODE_USE_BEDROCK in $tmp/out.
run_wrapper() {
    local fallback=$1
    shift
    rm -f "$tmp/out/tmux-argc" "$tmp/out/claude-argv" "$tmp/out/claude-bedrock"
    printf 'export BEDROCK_OPUS_FALLBACK_ARNS=%s\n' "$fallback" > "$tmp/home/.claudeenv"
    # shellcheck disable=SC2016 # $1 and $@ expand in the zsh child
    env -u TMUX HOME="$tmp/home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" \
        BEDROCK_OPUS_FALLBACK_ARNS="$fallback" CLAUDE_CODE_USE_BEDROCK=1 \
        zsh -f -c 'source "$1"; shift; "$@"' _ "$tmp/wrappers.zsh" "$@" > /dev/null 2>&1 || true
}

# result <file>: print a file under $tmp/out, or <missing>.
result() {
    if [[ -f "$tmp/out/$1" ]]; then cat "$tmp/out/$1"; else printf '<missing>'; fi
}

# shellcheck disable=SC2016 # the literal $(id) checks that an argument is never evaluated
args=(--resume abc --fork-session -n "two words" "semi;colon" "it's" '$(id)')
want_args=$(printf '%s\n' "${args[@]}")
work_flags=$(printf '%s\n' --model opus --fallback-model=fallback-arn --exclude-dynamic-system-prompt-sections)
plain_flags=$(printf '%s\n' --model opus --exclude-dynamic-system-prompt-sections)

run_wrapper fallback-arn claude
check "claude, no arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, no arguments: claude gets only the wrapper's flags" "$work_flags" "$(result claude-argv)"

run_wrapper fallback-arn claude "${args[@]}"
check "claude, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, eight arguments: claude gets each argument intact" \
    "$work_flags"$'\n'"$want_args" "$(result claude-argv)"

run_wrapper "" claude --resume abc
check "claude, empty fallback: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, empty fallback: no --fallback-model and the next flag intact" \
    "$plain_flags"$'\n'--resume$'\n'abc "$(result claude-argv)"

run_wrapper fallback-arn claude -n logs
check "claude, a subcommand name as an option value: still runs in tmux" "1" "$(result tmux-argc)"

wrong=()
for sub in agents attach auth auto-mode doctor gateway import install kill logs mcp plugin plugins purge respawn rm \
    setup-token stop ultrareview update upgrade; do
    run_wrapper fallback-arn claude "$sub" abc
    if [[ "$(result tmux-argc)" != "<missing>" || "$(result claude-argv)" != "$sub"$'\n'abc ]]; then
        wrong+=("$sub")
    fi
done
check "claude, each subcommand first: runs outside tmux with only its own arguments" "" "${wrong[*]}"

wrong=()
for flag in -h --help -v --version; do
    run_wrapper fallback-arn claude --resume abc "$flag"
    if [[ "$(result tmux-argc)" != "<missing>" || "$(result claude-argv)" != --resume$'\n'abc$'\n'"$flag" ]]; then
        wrong+=("$flag")
    fi
done
check "claude, help or version anywhere: runs outside tmux with only its own arguments" "" "${wrong[*]}"

wrong=()
for flag in -p --print --bg --background; do
    run_wrapper fallback-arn claude --resume abc "$flag"
    if [[ "$(result tmux-argc)" != "<missing>" \
        || "$(result claude-argv)" != "$work_flags"$'\n'--resume$'\n'abc$'\n'"$flag" ]]; then
        wrong+=("$flag")
    fi
done
check "claude, print or background anywhere: runs outside tmux with the wrapper's flags" "" "${wrong[*]}"

run_wrapper "" claude -p "say ok"
check "claude -p, empty fallback: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude -p, empty fallback: no --fallback-model and the prompt intact" \
    "$plain_flags"$'\n'-p$'\n'"say ok" "$(result claude-argv)"

run_wrapper fallback-arn claude-personal "${args[@]}"
check "claude-personal, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude-personal, eight arguments: claude gets each argument intact" \
    "$plain_flags"$'\n'"$want_args" "$(result claude-argv)"
check "claude-personal, eight arguments: Bedrock environment stripped" "<unset>" "$(result claude-bedrock)"

run_wrapper fallback-arn claude-personal --resume abc -p "say ok"
check "claude-personal -p: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude-personal -p: claude gets the wrapper's flags and each argument" \
    "$plain_flags"$'\n'--resume$'\n'abc$'\n'-p$'\n'"say ok" "$(result claude-argv)"
check "claude-personal -p: Bedrock environment stripped" "<unset>" "$(result claude-bedrock)"

run_wrapper fallback-arn claude-personal mcp list
check "claude-personal mcp list: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude-personal mcp list: claude gets only its own arguments" "mcp"$'\n'list "$(result claude-argv)"
check "claude-personal mcp list: Bedrock environment stripped" "<unset>" "$(result claude-bedrock)"

echo "-----"
echo "passed: $passes  failed: $failures"
[[ "$failures" -eq 0 ]]
