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
./hydrate.sh
```

### 4. Bootstrap (full setup)

```bash
./bootstrap.sh
```

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

Three layers of protection prevent leaking sensitive data:

1. **Pre-commit hook** (`.githooks/pre-commit`) — pattern-scans staged files
2. **Gitleaks** (`.gitleaks.toml`) — comprehensive secret detection, locally and in CI
3. **GitHub secret scanning + push protection** — enabled at the repository level

## Licence

[MIT](LICENSE)
