#!/usr/bin/env bash
# Tests for the claude() and claude-personal() wrappers in zsh/.zshrc.tmpl. Each case extracts the function, runs it
# under `zsh -f` with stub tmux, claude and slug scripts on PATH and a scratch HOME, and checks that tmux receives
# the pane command as one string (tmux runs several arguments directly, without a shell) and that claude receives
# exactly the arguments the wrapper was given.
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
if [[ "${1:-}" == auth ]]; then
    exit 0
fi
printf '%s\n' "$@" > "$WRAPPER_TEST_OUT/claude-argv"
EOF

printf '#!/usr/bin/env bash\necho c-test-0000\n' > "$tmp/home/.claude/scripts/derive-claude-slug.sh"
printf 'export BEDROCK_OPUS_FALLBACK_ARNS=fallback-arn\n' > "$tmp/home/.claudeenv"
chmod +x "$tmp/bin/tmux" "$tmp/bin/claude" "$tmp/home/.claude/scripts/derive-claude-slug.sh"

awk '/^claude\(\) \{$/,/^}$/; /^claude-personal\(\) \{$/,/^}$/' "$repo_root/zsh/.zshrc.tmpl" > "$tmp/wrappers.zsh"

# run_wrapper <function> [arg...]: run the wrapper; leave tmux's argument count and claude's argv in $tmp/out.
run_wrapper() {
    rm -f "$tmp/out/tmux-argc" "$tmp/out/claude-argv"
    # shellcheck disable=SC2016 # $1 and $@ expand in the zsh child
    env -u TMUX HOME="$tmp/home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" \
        zsh -f -c 'source "$1"; shift; "$@"' _ "$tmp/wrappers.zsh" "$@" > /dev/null 2>&1 || true
}

# result <file>: print a file under $tmp/out, or <missing>.
result() {
    if [[ -f "$tmp/out/$1" ]]; then cat "$tmp/out/$1"; else printf '<missing>'; fi
}

# shellcheck disable=SC2016 # the literal $(id) checks that an argument is never evaluated
args=(--resume abc --fork-session -p "two words" "semi;colon" "it's" '$(id)')
want_args=$(printf '%s\n' "${args[@]}")
work_flags=$(printf '%s\n' --model opus --fallback-model fallback-arn --exclude-dynamic-system-prompt-sections)
personal_flags=$(printf '%s\n' --model opus --exclude-dynamic-system-prompt-sections)

run_wrapper claude
check "claude, no arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, no arguments: claude gets only the wrapper's flags" "$work_flags" "$(result claude-argv)"

run_wrapper claude "${args[@]}"
check "claude, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, eight arguments: claude gets each argument intact" \
    "$work_flags"$'\n'"$want_args" "$(result claude-argv)"

run_wrapper claude-personal "${args[@]}"
check "claude-personal, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude-personal, eight arguments: claude gets each argument intact" \
    "$personal_flags"$'\n'"$want_args" "$(result claude-argv)"

echo "-----"
echo "passed: $passes  failed: $failures"
[[ "$failures" -eq 0 ]]
