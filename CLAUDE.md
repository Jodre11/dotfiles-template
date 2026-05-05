# Dotfiles Repository

This repo manages macOS dotfiles using GNU Stow. All config files live in
package directories and are symlinked into `~` by Stow.

`bootstrap.sh` is macOS-specific (Homebrew, Stow, Xcode CLI tools). It also
clones claude-settings into `~/.claude` and runs `setup-platform.sh` to
configure machine-specific Claude Code settings.

## Key Rules

- After editing any config file in this repo (or its symlinked target in `~`),
  remind the user to commit and push the changes
- After installing or removing a Homebrew package, remind the user to regenerate
  the Brewfile: `brew bundle dump --file=~/dotfiles/Brewfile --force`
- Do not add secrets, SSH keys, or credentials to this repo
- Keep `bootstrap.sh` idempotent — every command must be safe to re-run
- When adding a new config file, create a new Stow package following the existing
  pattern rather than adding it to an unrelated package
- Follow the security invariants documented in `SECURITY.md`
- All shell scripts must pass `shellcheck --severity=warning`

## Template Strategy

Files with sensitive content use `.tmpl` extensions with `__PLACEHOLDER__` tokens.
`hydrate.sh` reads `config.env` and produces real files. Run `hydrate.sh` before
`stow` — the generated files are what get symlinked into `~`.

## SSH Keys

SSH keys are stored in the Bitwarden vault and served via the Bitwarden SSH
agent. There are no private key files on disk.

- **macOS/Linux**: `.zshrc` sets `SSH_AUTH_SOCK` to the agent socket path
  configured in `config.env`
- `.gitconfig` uses an inline public key for commit signing. The Bitwarden
  desktop app must be running and unlocked for SSH operations to work.
