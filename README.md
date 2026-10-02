# Dotfiles Template

Fork-ready macOS dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/),
idempotent bootstrap, push-to-talk whisper dictation, and a `config.env` placeholder
strategy for keeping sensitive values out of version control.

## What's Included

### Stow Packages

| Package | Contents |
|---|---|
| `aws` | AWS CLI SSO profiles (template) |
| `chrome` | Chrome dev/Playwright hardening script |
| `docker` | Docker Desktop config (template) + daemon settings |
| `editorconfig` | Cross-IDE formatting rules |
| `firefox` | Arkenfox-based hardening setup |
| `gh` | GitHub CLI config |
| `ghostty` | Ghostty terminal config |
| `git` | Git config with delta, strongbox, SSH signing (template) |
| `hammerspoon` | Push-to-talk dictation, Karabiner BLE watchdog, middle-click paste |
| `homebrew` | Homebrew update check LaunchAgent |
| `karabiner` | Karabiner-Elements key remapping |
| `mcp` | MCP server config for Claude Code (template) |
| `scripts` | Datadog MCP wrapper (template) |
| `ssh` | SSH config with agent socket (template) |
| `starship` | Starship prompt theme |
| `tmux` | tmux config with clipboard integration |
| `vscode` | VS Code settings |
| `zsh` | zsh config, Bedrock env vars, Oh My Zsh plugins (template) |

### Other Files

| File | Purpose |
|---|---|
| `bootstrap.sh` | Idempotent macOS setup (Homebrew, Stow, dev tools, whisper models) |
| `Brewfile` | Homebrew packages with section comments |
| `hydrate.sh` | Generate config files from templates using `config.env` |
| `docs/whisper-prompt-technique.md` | Guide for domain-specific whisper prompts |

## Getting Started

### 1. Fork and clone

```bash
git clone git@github.com:youruser/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 2. Configure

```bash
cp config.env.example config.env
# Edit config.env with your values
```

### 3. Hydrate templates

```bash
./hydrate.sh --diff   # preview: print each changed output's diff, write nothing
./hydrate.sh          # write every output, reporting NEW, CHANGED or UNCHANGED
```

### 4. Bootstrap (full setup)

```bash
./bootstrap.sh
```

Bootstrap clones claude-settings into `~/.claude`, then stops once and asks you to create
`~/.claude/config.env` from its `config.env.example`. Create it only after that clone: a
`~/.claude` that is not a git repository is moved to `~/.claude.bak`. Then re-run
`./bootstrap.sh`, which hydrates Claude Code's settings before its platform setup.

Or just link specific packages:

```bash
stow -v -t ~ zsh git ghostty starship tmux
```

## Template Strategy

Files with sensitive content use a `.tmpl` extension containing `__PLACEHOLDER__` tokens.
`hydrate.sh` reads `config.env` and produces real files (without `.tmpl`). Stow symlinks the
real files — `.tmpl` files are never symlinked. Generated files are `.gitignore`d in the
template repo.

| Template | Generated | Key Placeholders |
|---|---|---|
| `aws/.aws/config.tmpl` | `aws/.aws/config` | `__SSO_START_URL__`, profiles from array |
| `docker/.docker/config.json.tmpl` | `docker/.docker/config.json` | (no placeholders — `auths: {}` populated at runtime) |
| `git/.gitconfig.tmpl` | `git/.gitconfig` | `__GIT_USER_NAME__`, `__GIT_USER_EMAIL__`, `__GIT_SIGNING_KEY__` |
| `mcp/.mcp.json.tmpl` | `mcp/.mcp.json` | `__DATADOG_MCP_SCRIPT__` |
| `scripts/datadog-mcp.sh.tmpl` | `scripts/datadog-mcp.sh` | `__DATADOG_SITE__` |
| `ssh/.ssh/config.tmpl` | `ssh/.ssh/config` | `__SSH_AGENT_SOCK__` |
| `zsh/.claudeenv.tmpl` | `zsh/.claudeenv` | `__BEDROCK_*__` |
| `zsh/.zprofile.tmpl` | `zsh/.zprofile` | `__JETBRAINS_TOOLBOX_PATH__` |
| `zsh/.zshrc.tmpl` | `zsh/.zshrc` | `__SSH_AGENT_SOCK__`, `__NUGET_NAMESPACE__` |

## Secret Scanning

Four layers keep sensitive data out of the repository:

1. **Pre-commit hook** (`.githooks/pre-commit`) — scans every added line for secret-shaped values and identity
   markers (the patterns are in `.githooks/guard-config.sh`), then runs gitleaks over the staged changes, including
   content gitleaks' own diff cannot read.
2. **Pre-push hook** (`.githooks/pre-push`) — repeats those scans over every commit a push would publish, so a commit
   made without the pre-commit (a rebase, a cherry-pick, `git am`, or the hooks turned off) is caught before it
   leaves the machine. It also scans each commit's message, author and committer, and each annotated tag's message,
   tagger and name, and refuses a ref that names a blob or a tree.
3. **CI** — gitleaks, a pattern-sync check (`tests/test-pattern-sync.sh`) and an output-ignore check
   (`tests/test-output-ignore.sh`) run on every push to `main` and every pull request into it.
4. **GitHub secret scanning and push protection** — enabled at the repository level.

`bootstrap.sh` activates both hooks by setting a repo-local `core.hooksPath .githooks`; git does not do this on
clone. The hooks use gitleaks 8.25.0 or later (8.30.1 is tested); without it they warn and run the pattern scan
only. So that no uncommitted edit decides a scan, a commit or push is refused while `.githooks/guard-config.sh` is
not exactly its staged copy, a commit while `.gitleaks.toml` or `.gitleaksignore` differs from its staged copy, and
a push of commits whose tip commits a different `guard-config.sh` from the one in use.

### Local pattern lists

To screen for names you must not publish without publishing the list, put them in `.githooks/identity-patterns.local`
(organisation and personal identity markers) and `.githooks/always-patterns.local` (secret-shaped literals such as
account IDs). Each holds one POSIX ERE per line, matched case-insensitively; blank lines and lines starting with `#`
are ignored. Both are gitignored, either may be a symlink to a list kept elsewhere, and the hooks refuse to commit or
push either one. A list that cannot be read, holds no pattern, or holds a pattern with leading or trailing
whitespace or one awk cannot match as written stops the commit rather than being skipped. The lists also apply to
`.githooks/guard-config.sh`, `.githooks/pre-commit` and `.gitleaks.toml`, which are exempt only from the tracked
patterns they define. In a linked worktree (`git worktree add`), the hooks also read the main worktree's lists, or
warn when git cannot name the main worktree (a git directory kept apart with `--separate-git-dir`).

A repository can disregard a local identity pattern that is its own public identity, such as the owner's handle in a
repository published under it: put the pattern's exact text in `LOCAL_IDENTITY_IGNORE` in `.githooks/guard-config.sh`.
An entry must equal a line of the list exactly, so a pattern that later changes bites again, and an ignored pattern
is still checked, so a malformed list still stops the commit. `always-patterns.local` and the tracked patterns cannot
be opted out of. The array is committed like any other guard setting, so every opt-out is a reviewed change.

### Bypasses

`SKIP_PATTERN_SCAN=1 git commit` (or `git push`) skips the pattern scan only, for a file that must carry a pattern;
say so in the commit body. gitleaks always runs and has no bypass: clear a false positive with a targeted
`[[allowlists]]` entry in `.gitleaks.toml`, committed with the change. gitleaks never reads `.gitleaks.toml` itself,
and its default allowlist keeps its custom rules out of some other paths (images, PDFs, lockfiles, `node_modules/`
and the like), so under the bypass only its built-in rules scan those files.

## Licence

[MIT](LICENSE)
