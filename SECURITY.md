# Security Conventions

This document records the security invariants enforced across this repository.
Follow these when adding or modifying scripts and configuration.

## Shell Scripts

- **No `eval`** — never evaluate dynamically constructed strings. Template
  hydration uses bash parameter expansion (`${var//pattern/replacement}`) which
  is pure string substitution.
- **No unquoted expansions in command strings** — variables interpolated into
  commands passed to `sh -c`, `osascript`, or similar must be quoted or
  sanitised. Prefer passing arguments positionally over string concatenation.
- **`set -euo pipefail`** — all scripts must enable strict mode on the first
  executable line.
- **Pin external scripts** — any installer fetched via `curl | sh` must use a
  pinned commit hash or versioned URL, not a mutable `HEAD`/`master` reference.

## Secrets Management

- **Never commit secrets** — credentials, API keys, and tokens belong in
  `config.env` (git-ignored), Bitwarden vault, envchain, or
  `~/.config/<service>/env` (chmod 600).
- **Gitleaks + pre-commit hooks** — `.gitleaks.toml` defines patterns; the
  pre-commit hook in `.githooks/` runs gitleaks on every commit. CI runs the
  same check via GitHub Actions.
- **No private keys on disk** — SSH keys are served by the Bitwarden SSH agent.
  `.gitconfig` references the public key inline for commit signing.
- **Subprocess env scrubbing** — `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` prevents
  credential leakage from AI coding tools into child processes.

## Template Hydration

- `hydrate.sh` replaces `__PLACEHOLDER__` tokens using bash string substitution.
  It does not use `eval`, `envsubst`, or any mechanism that interprets shell
  metacharacters in config values.
- Generated (hydrated) files are git-ignored. Only `.tmpl` sources are committed.

## CI Gates

- **Gitleaks** — scans for accidental secret commits on every push and PR.
- **Pattern sync test** — verifies pre-commit hook patterns stay aligned with
  `.gitleaks.toml`.
- **ShellCheck** — static analysis of all `.sh` and `.sh.tmpl` files at
  `--severity=warning` or above. Exclusions are centralised in `.shellcheckrc`.

## Dependency Pinning

- GitHub Actions use full commit SHAs (not tags) to prevent supply-chain attacks
  via tag mutation.
- Oh My Zsh, zsh-syntax-highlighting, and zsh-autosuggestions are cloned at
  pinned commits or tags.
- Homebrew install script is fetched at a pinned commit.
