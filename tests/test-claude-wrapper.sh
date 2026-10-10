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

# A HOME holding a space proves the pane command string quotes every path it interpolates.
home="$tmp/home dir"
mkdir -p "$tmp/bin" "$home/.claude/scripts" "$tmp/out"
printf '%s\n' '{}' >"$home/.claude/settings.work.json"

cat > "$tmp/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 1 ;;
    show-environment) [[ -z ${TMUX_TEST_GLOBAL_ENV-} ]] || printf '%s\n' "$TMUX_TEST_GLOBAL_ENV" ;;
    new-session)
        shift 3
        printf '%s' "$#" > "$WRAPPER_TEST_OUT/tmux-argc"
        # The pane inherits the server's global environment, which the calling shell never held.
        while IFS= read -r line; do
            [[ $line == *=* ]] && export "$line"
        done <<< "${TMUX_TEST_GLOBAL_ENV-}"
        exec zsh -f -c "$1"
        ;;
esac
exit 0
EOF

# The claude stub records its argv and, for each variable the cases inspect, its value or <unset>.
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WRAPPER_TEST_OUT/claude-argv"
for name in CLAUDE_CODE_USE_BEDROCK AWS_REGION ANTHROPIC_MODEL AWS_PROFILE TEST_NUGET_PAT INDENTED_VAR \
    CLAUDE_CODE_NO_FLICKER ENVCHAIN_RAN STALE_NUGET_PAT; do
    printf '%s=%s\n' "$name" "${!name-<unset>}"
done > "$WRAPPER_TEST_OUT/claude-env"
EOF

# The envchain stub logs each call; ENVCHAIN_TEST_RC makes every call fail with that status, as a locked keychain or
# a missing namespace would. Otherwise it runs the command with the namespace's PAT, as envchain does.
cat > "$tmp/bin/envchain" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WRAPPER_TEST_OUT/envchain-calls"
if [[ -n ${ENVCHAIN_TEST_RC-} ]]; then
    exit "$ENVCHAIN_TEST_RC"
fi
ns=$1
shift
ENVCHAIN_RAN=$ns TEST_NUGET_PAT=from-keychain exec "$@"
EOF

# The sleep stub logs its argument and returns at once, so a pane held open to show an error costs no time.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$WRAPPER_TEST_OUT/sleep-argv"\n' > "$tmp/bin/sleep"

for tool in dotnet jb; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$WRAPPER_TEST_OUT/%s-argv"\n' "$tool" >"$tmp/bin/$tool"
done

printf '#!/usr/bin/env bash\necho c-test-0000\n' > "$home/.claude/scripts/derive-claude-slug.sh"
chmod +x "$tmp/bin/"* "$home/.claude/scripts/derive-claude-slug.sh"

# Extract the wrappers, once with a configured namespace and once with none.
extracted=$(awk '/^claude-arg-mode\(\) \{$/,/^}$/; /^claude-work-vars\(\) \{$/,/^}$/;
    /^claude-launch-env\(\) \{$/,/^}$/; /^claude\(\) \{$/,/^}$/; /^claude-personal\(\) \{$/,/^}$/;
    /^if \[\[ -n "__NUGET_NAMESPACE__" \]\]; then$/,/^fi$/' \
    "$repo_root/zsh/.zshrc.tmpl")
printf '%s\n' "${extracted//__NUGET_NAMESPACE__/testns}" > "$tmp/wrappers.zsh"
printf '%s\n' "${extracted//__NUGET_NAMESPACE__/}" > "$tmp/wrappers-nons.zsh"
wrappers="$tmp/wrappers.zsh"
extra_env=()

# Claude Code's shell snapshot drops functions whose names start with _, so a wrapper calling one fails in the ! and
# Bash-tool shells.
check "the wrappers call no _-prefixed function" "" \
    "$(grep -oE '^[[:space:]]+_[[:alnum:]_-]+' "$tmp/wrappers.zsh" | tr -d '[:space:]' || true)"
check "the argument classifier is extracted" "1" "$(grep -c '^claude-arg-mode() {$' "$tmp/wrappers.zsh" || true)"
check "the NuGet shim block is extracted" "1" "$(grep -c '^    dotnet() {$' "$tmp/wrappers.zsh" || true)"

# write_claudeenv <fallback>: write a scratch ~/.claudeenv shaped like the real one, plus a commented-out and an
# indented export for the parser cases.
write_claudeenv() {
    printf '%s\n' '# Clean slate' 'unset ANTHROPIC_MODEL' 'export CLAUDE_CODE_USE_BEDROCK=1' \
        'export AWS_REGION=fixture-region' "export ANTHROPIC_MODEL='fixture-model'" \
        "export AWS_PROFILE='fixture-profile'" "export BEDROCK_OPUS_FALLBACK_ARNS=$1" '# export COMMENTED_OUT=1' \
        '    export INDENTED_VAR=1' > "$home/.claudeenv"
}

# run_wrapper <fallback> <function> [arg...]: run <function> from $wrappers under `env -i` and zsh -f, so the
# runner's own environment (CLAUDECODE, TMUX, a real *_NUGET_PAT) cannot leak in. The parent holds stale work
# variables, as a shell started before the change would; extra_env adds more. Leaves tmux's argument count, claude's
# argv and environment, envchain's calls, the wrapper's stderr and exit status, and the parent shell's ANTHROPIC_MODEL
# after the call in $tmp/out.
run_wrapper() {
    local fallback=$1
    shift
    rm -f "$tmp/out/"*
    write_claudeenv "$fallback"
    # shellcheck disable=SC2016 # $1, $@ and $? expand in the zsh child
    env -i HOME="$home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" CLAUDE_CODE_USE_BEDROCK=1 \
        AWS_PROFILE=hand-set TEST_NUGET_PAT=hand-set \
        ${extra_env[@]+"${extra_env[@]}"} \
        zsh -f -c 'source "$1"; shift; "$@"; print -rn -- $? > "$WRAPPER_TEST_OUT/rc"
            print -rn -- "${ANTHROPIC_MODEL-<unset>}" > "$WRAPPER_TEST_OUT/parent-model"' \
        _ "$wrappers" "$@" > /dev/null 2> "$tmp/out/stderr" || true
}

# result <file>: print a file under $tmp/out, or <missing>.
result() {
    if [[ -f "$tmp/out/$1" ]]; then cat "$tmp/out/$1"; else printf '<missing>'; fi
}

# envval <name>: print the value claude saw for <name>, or <missing> when claude did not run.
envval() {
    if [[ -f "$tmp/out/claude-env" ]]; then sed -n "s/^$1=//p" "$tmp/out/claude-env"; else printf '<missing>'; fi
}

# shellcheck disable=SC2016 # the literal $(id) checks that an argument is never evaluated
args=(--resume abc --fork-session -n "two words" "semi;colon" "it's" '$(id)')
want_args=$(printf '%s\n' "${args[@]}")
exclude=--exclude-dynamic-system-prompt-sections
ws="$home/.claude/settings.work.json"
work_tmux=$(printf '%s\n' --model opus --fallback-model=fallback-arn --settings "$ws" "$exclude")
work_direct=$work_tmux
nofb_tmux=$(printf '%s\n' --model opus --settings "$ws" "$exclude")
nofb_direct=$nofb_tmux
personal_settings='{"disabledMcpjsonServers":["datadog"]}'
personal_tmux=$(printf '%s\n' --model opus --settings "$personal_settings" "$exclude")
personal_direct=$personal_tmux

run_wrapper fallback-arn claude
check "claude, no arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, no arguments: claude gets only the wrapper's flags" "$work_tmux" "$(result claude-argv)"

run_wrapper fallback-arn claude "${args[@]}"
check "claude, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, eight arguments: claude gets each argument intact" \
    "$work_tmux"$'\n'"$want_args" "$(result claude-argv)"

run_wrapper "" claude --resume abc
check "claude, empty fallback: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude, empty fallback: no --fallback-model and the next flag intact" \
    "$nofb_tmux"$'\n'--resume$'\n'abc "$(result claude-argv)"

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
        || "$(result claude-argv)" != "$work_direct"$'\n'--resume$'\n'abc$'\n'"$flag" ]]; then
        wrong+=("$flag")
    fi
done
check "claude, print or background anywhere: runs outside tmux with the wrapper's flags" "" "${wrong[*]}"

run_wrapper "" claude -p "say ok"
check "claude -p, empty fallback: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude -p, empty fallback: no --fallback-model and the prompt intact" \
    "$nofb_direct"$'\n'-p$'\n'"say ok" "$(result claude-argv)"

run_wrapper fallback-arn claude-personal "${args[@]}"
check "claude-personal, eight arguments: tmux gets one command string" "1" "$(result tmux-argc)"
check "claude-personal, eight arguments: claude gets each argument intact" \
    "$personal_tmux"$'\n'"$want_args" "$(result claude-argv)"
check "claude-personal, eight arguments: Bedrock environment stripped" "<unset>" "$(envval CLAUDE_CODE_USE_BEDROCK)"

run_wrapper fallback-arn claude-personal --resume abc -p "say ok"
check "claude-personal -p: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude-personal -p: claude gets the wrapper's flags and each argument" \
    "$personal_direct"$'\n'--resume$'\n'abc$'\n'-p$'\n'"say ok" "$(result claude-argv)"
check "claude-personal -p: Bedrock environment stripped" "<unset>" "$(envval CLAUDE_CODE_USE_BEDROCK)"

run_wrapper fallback-arn claude-personal mcp list
check "claude-personal mcp list: runs outside tmux" "<missing>" "$(result tmux-argc)"
check "claude-personal mcp list: claude gets only its own arguments" "mcp"$'\n'list "$(result claude-argv)"
check "claude-personal mcp list: Bedrock environment stripped" "<unset>" "$(envval CLAUDE_CODE_USE_BEDROCK)"

# --- the strip list is derived from ~/.claudeenv
write_claudeenv fallback-arn
# shellcheck disable=SC2016 # reply expands in the zsh child
got=$(env -i HOME="$home" PATH="$tmp/bin:$PATH" TEST_NUGET_PAT=x OTHER_NUGET_PAT=y \
    zsh -f -c 'source "$1"; claude-work-vars; print -l -- ${(o)reply}' _ "$wrappers")
check "claude-work-vars: every exported name, AWS_PROFILE and each *_NUGET_PAT, once, nothing commented out" \
    "$(printf '%s\n' ANTHROPIC_MODEL AWS_PROFILE AWS_REGION BEDROCK_OPUS_FALLBACK_ARNS CLAUDE_CODE_USE_BEDROCK \
        INDENTED_VAR OTHER_NUGET_PAT TEST_NUGET_PAT)" "$got"

# shellcheck disable=SC2016 # reply expands in the zsh child
got=$(env -i HOME="$home" PATH="$tmp/bin:$PATH" TEST_NUGET_PAT=x \
    TMUX_TEST_GLOBAL_ENV=$'STALE_NUGET_PAT=x\nNOT_A_PAT=y\n# NUGET_PAT=z\nTEST_NUGET_PAT=x' \
    zsh -f -c 'source "$1"; claude-work-vars; print -l -- ${(o)reply}' _ "$wrappers")
check "claude-work-vars: a *_NUGET_PAT held only by the tmux server is included, once" \
    "$(printf '%s\n' ANTHROPIC_MODEL AWS_PROFILE AWS_REGION BEDROCK_OPUS_FALLBACK_ARNS CLAUDE_CODE_USE_BEDROCK \
        INDENTED_VAR STALE_NUGET_PAT TEST_NUGET_PAT)" "$got"

rm -f "$home/.claudeenv"
# shellcheck disable=SC2016 # reply expands in the zsh child
got=$(env -i HOME="$home" PATH="$tmp/bin:$PATH" \
    zsh -f -c 'source "$1"; claude-work-vars; print -l -- ${(o)reply}' _ "$wrappers")
check "claude-work-vars, no ~/.claudeenv: AWS_PROFILE and CLAUDE_CODE_USE_BEDROCK still included" \
    "$(printf '%s\n' AWS_PROFILE CLAUDE_CODE_USE_BEDROCK)" "$got"
write_claudeenv fallback-arn

# personal_stripped: print the work variables claude still saw, or nothing when every one was stripped.
personal_stripped() {
    local name left=""
    for name in CLAUDE_CODE_USE_BEDROCK AWS_REGION ANTHROPIC_MODEL AWS_PROFILE TEST_NUGET_PAT INDENTED_VAR; do
        [[ "$(envval "$name")" == "<unset>" ]] || left+=" $name"
    done
    printf '%s' "$left"
}

run_wrapper fallback-arn claude-personal --resume abc
check "claude-personal, tmux: the pane strips every work variable the parent still holds" "" "$(personal_stripped)"
check "claude-personal, tmux: the launch line carries the inline flags" "1" "$(envval CLAUDE_CODE_NO_FLICKER)"

run_wrapper fallback-arn claude-personal -p "say ok"
check "claude-personal -p: every work variable stripped" "" "$(personal_stripped)"
check "claude-personal -p: the launch line carries the inline flags" "1" "$(envval CLAUDE_CODE_NO_FLICKER)"

run_wrapper fallback-arn claude-personal mcp list
check "claude-personal mcp list: every work variable stripped" "" "$(personal_stripped)"

extra_env=(TMUX_TEST_GLOBAL_ENV=STALE_NUGET_PAT=x)
run_wrapper fallback-arn claude-personal --resume abc
check "claude-personal, tmux: a *_NUGET_PAT only the tmux server holds is stripped" "<unset>" \
    "$(envval STALE_NUGET_PAT)"
extra_env=()

rm -f "$tmp/out/"* "$home/.claudeenv"
# shellcheck disable=SC2016 # $1 and $@ expand in the zsh child
env -i HOME="$home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" AWS_PROFILE=hand-set TEST_NUGET_PAT=hand-set \
    zsh -f -c 'source "$1"; shift; "$@"' _ "$wrappers" claude-personal -p "say ok" > /dev/null 2>&1 || true
check "claude-personal, no ~/.claudeenv: still runs" "$personal_direct"$'\n'-p$'\n'"say ok" "$(result claude-argv)"
check "claude-personal, no ~/.claudeenv: AWS_PROFILE and the NuGet PAT still stripped" "<unset> <unset>" \
    "$(envval AWS_PROFILE) $(envval TEST_NUGET_PAT)"

extra_env=(CLAUDECODE=1)
run_wrapper fallback-arn claude-personal --resume abc
check "claude-personal inside Claude Code: the plain binary, with only the caller's arguments" \
    --resume$'\n'abc "$(result claude-argv)"
check "claude-personal inside Claude Code: no tmux" "<missing>" "$(result tmux-argc)"
check "claude-personal inside Claude Code: the session's own environment" "hand-set" "$(envval AWS_PROFILE)"
extra_env=()

# --- claude(): scoped ~/.claudeenv, the work layer and the NuGet PAT
run_wrapper fallback-arn claude --resume abc
check "claude, tmux: the pane sources ~/.claudeenv" "fixture-model" "$(envval ANTHROPIC_MODEL)"
check "claude, tmux: the parent shell is untouched" "<unset>" "$(result parent-model)"
check "claude, tmux: runs under the namespace's envchain" "testns from-keychain" \
    "$(envval ENVCHAIN_RAN) $(envval TEST_NUGET_PAT)"
check "claude, tmux: the launch line carries the inline flags" "1" "$(envval CLAUDE_CODE_NO_FLICKER)"

run_wrapper fallback-arn claude -p "say ok"
check "claude -p: the work layer and the fallback from ~/.claudeenv" "$work_direct"$'\n'-p$'\n'"say ok" \
    "$(result claude-argv)"
check "claude -p: ~/.claudeenv is sourced for the call only" "fixture-model <unset>" \
    "$(envval ANTHROPIC_MODEL) $(result parent-model)"
check "claude -p: runs under the namespace's envchain" "testns" "$(envval ENVCHAIN_RAN)"

run_wrapper fallback-arn claude auth status
check "claude auth status: bare, with no work layer" "auth"$'\n'status "$(result claude-argv)"
check "claude auth status: ~/.claudeenv is sourced for the call only" "fixture-model <unset>" \
    "$(envval ANTHROPIC_MODEL) $(result parent-model)"
check "claude auth status: no envchain" "<unset>" "$(envval ENVCHAIN_RAN)"

wrappers="$tmp/wrappers-nons.zsh"
run_wrapper fallback-arn claude --resume abc
check "claude, no namespace: no envchain call" "<missing>" "$(result envchain-calls)"
check "claude, no namespace: still launches" "$work_tmux"$'\n'--resume$'\n'abc "$(result claude-argv)"
wrappers="$tmp/wrappers.zsh"

extra_env=(ENVCHAIN_TEST_RC=1)
run_wrapper fallback-arn claude --resume abc
check "claude, envchain unavailable: launches without it" "$work_tmux"$'\n'--resume$'\n'abc "$(result claude-argv)"
check "claude, envchain unavailable: no PAT from the keychain" "<unset>" "$(envval ENVCHAIN_RAN)"
check "claude, envchain unavailable: warns in the parent shell" "1" \
    "$(grep -c 'starting without the NuGet PAT' "$tmp/out/stderr" || true)"
extra_env=()

rm "$home/.claude/settings.work.json"
for flags in "--resume abc" "-p ok"; do
    # shellcheck disable=SC2086 # split into the wrapper's arguments on purpose
    run_wrapper fallback-arn claude $flags
    check "claude $flags, no work layer: refuses" "<missing> 1" "$(result claude-argv) $(result rc)"
    check "claude $flags, no work layer: names the remedy" "1" \
        "$(grep -c 'apply-settings.sh' "$tmp/out/stderr" || true)"
done
printf '%s\n' '{}' > "$home/.claude/settings.work.json"

# run_wrapper always writes ~/.claudeenv, so this case runs by hand.
rm -f "$tmp/out/"* "$home/.claudeenv"
# shellcheck disable=SC2016 # $1, $@ and $? expand in the zsh child
env -i HOME="$home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" zsh -f -c \
    'source "$1"; shift; "$@"; print -rn -- $? > "$WRAPPER_TEST_OUT/rc"' _ "$wrappers" claude --resume abc \
    > /dev/null 2> "$tmp/out/stderr" || true
check "claude, no ~/.claudeenv: refuses tmux mode" "<missing> 1" "$(result claude-argv) $(result rc)"
check "claude, no ~/.claudeenv: names the remedy" "1" "$(grep -c 'hydrate.sh' "$tmp/out/stderr" || true)"
rm -f "$tmp/out/"*
# shellcheck disable=SC2016 # $1 and $@ expand in the zsh child
env -i HOME="$home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" zsh -f -c \
    'source "$1"; shift; "$@"' _ "$wrappers" claude --version > /dev/null 2> "$tmp/out/stderr" || true
check "claude --version, no ~/.claudeenv: still runs, first-party" "--version <unset>" \
    "$(result claude-argv) $(envval CLAUDE_CODE_USE_BEDROCK)"
check "claude --version, no ~/.claudeenv: warns" "1" "$(grep -c 'hydrate.sh' "$tmp/out/stderr" || true)"

# check_refusals <fixture>: with the ~/.claudeenv written for <fixture> (the lines after it), each of claude's three
# modes must refuse: claude never runs, the status is non-zero and stderr names hydrate.sh.
check_refusals() {
    local fixture=$1 label mode_args
    shift
    for mode_args in "tmux:--resume abc" "direct:-p ok" "bare:auth status"; do
        label=${mode_args%%:*}
        rm -f "$tmp/out/"*
        printf '%s\n' "$@" > "$home/.claudeenv"
        # shellcheck disable=SC2016,SC2086 # $1, $@ and $? expand in the zsh child; the arguments split on purpose
        env -i HOME="$home" PATH="$tmp/bin:$PATH" WRAPPER_TEST_OUT="$tmp/out" zsh -f -c \
            'source "$1"; shift; "$@"; print -rn -- $? > "$WRAPPER_TEST_OUT/rc"' _ "$wrappers" claude \
            ${mode_args#*:} > /dev/null 2> "$tmp/out/stderr" || true
        check "claude $label, $fixture: claude does not run, status non-zero" "<missing> 1" \
            "$(result claude-argv) $(result rc)"
        check "claude $label, $fixture: names the remedy" "1" "$(grep -c 'hydrate.sh' "$tmp/out/stderr" || true)"
        if [[ $label == tmux ]]; then
            check "claude tmux, $fixture: the pane stays open to show the error" "5" "$(result sleep-argv)"
        fi
    done
}

check_refusals "an unparseable ~/.claudeenv" 'export CLAUDE_CODE_USE_BEDROCK=1' 'if [[ '
check_refusals "a ~/.claudeenv without CLAUDE_CODE_USE_BEDROCK=1" '# Clean slate' 'export AWS_REGION=fixture-region'
check_refusals "a ~/.claudeenv with CLAUDE_CODE_USE_BEDROCK=0" 'export CLAUDE_CODE_USE_BEDROCK=0'
write_claudeenv fallback-arn

extra_env=(CLAUDECODE=1)
run_wrapper fallback-arn claude --resume abc
check "claude inside Claude Code: the plain binary, with only the caller's arguments" --resume$'\n'abc \
    "$(result claude-argv)"
check "claude inside Claude Code: no tmux and no envchain" "<missing> <missing>" \
    "$(result tmux-argc) $(result envchain-calls)"
extra_env=()

# --- no interactive shell gets the Bedrock environment or the NuGet PAT
zshrc="$repo_root/zsh/.zshrc.tmpl"
claudeenv_tmpl="$repo_root/zsh/.claudeenv.tmpl"
neutral='CLAUDE_CODE_NO_FLICKER|ENABLE_TOOL_SEARCH|ENABLE_PROMPT_CACHING_1H|CLAUDE_CODE_SUBPROCESS_ENV_SCRUB'
neutral+='|CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE|CLAUDE_CODE_WORKFLOWS|CLAUDE_CODE_ENABLE_AUTO_MODE'
neutral+='|ENABLE_LSP_TOOL'
check ".zshrc sources ~/.claudeenv nowhere outside claude()" "0" \
    "$(grep -cE '^\[ -f "\$HOME/\.claudeenv" \]' "$zshrc" || true)"
check ".zshrc exports no NuGet PAT" "0" \
    "$(grep -cE 'envchain __NUGET_NAMESPACE__ env|export .*_NUGET_PAT' "$zshrc" || true)"
check ".zshrc takes AWS_REGION from config.env" "1" \
    "$(grep -cxF "export AWS_REGION='__AWS_REGION__'" "$zshrc" || true)"
check ".claudeenv carries no provider-neutral flag" "0" "$(grep -cE "$neutral" "$claudeenv_tmpl" || true)"
check ".claudeenv exports the Bedrock AWS profile" "1" \
    "$(grep -cxF "export AWS_PROFILE='__BEDROCK_AWS_PROFILE__'" "$claudeenv_tmpl" || true)"
check "every .claudeenv line is a comment, an unset or an export NAME=" "" \
    "$(grep -vE '^(#.*|unset [A-Za-z_][A-Za-z0-9_]*|export [A-Za-z_][A-Za-z0-9_]*=.*)?$' "$claudeenv_tmpl" || true)"

# --- the NuGet shims
run_wrapper fallback-arn dotnet restore x
check "dotnet: runs under the namespace's envchain" "testns dotnet restore x" "$(result envchain-calls)"
check "dotnet: gets its arguments" "restore"$'\n'x "$(result dotnet-argv)"
run_wrapper fallback-arn jb inspectcode s.sln
check "jb: runs under the namespace's envchain" "testns jb inspectcode s.sln" "$(result envchain-calls)"
extra_env=(ENVCHAIN_TEST_RC=3)
run_wrapper fallback-arn dotnet restore
check "dotnet: returns envchain's exit status" "3" "$(result rc)"
extra_env=(CLAUDECODE=1)
run_wrapper fallback-arn dotnet restore
check "dotnet inside Claude Code: the plain binary, no envchain" "<missing> restore" \
    "$(result envchain-calls) $(result dotnet-argv)"
run_wrapper fallback-arn jb inspectcode
check "jb inside Claude Code: the plain binary, no envchain" "<missing> inspectcode" \
    "$(result envchain-calls) $(result jb-argv)"
extra_env=()
# shellcheck disable=SC2016 # whence runs in the zsh child
check "no namespace: no dotnet or jb shim is defined" "dotnet: command jb: command" \
    "$(env -i PATH="$tmp/bin:$PATH" zsh -f -c 'source "$1"; print -rn -- "$(whence -w dotnet) $(whence -w jb)"' \
        _ "$tmp/wrappers-nons.zsh")"

echo "-----"
echo "passed: $passes  failed: $failures"
[[ "$failures" -eq 0 ]]
