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
- **Git hooks + gitleaks** — `.githooks/guard-config.sh` and `.gitleaks.toml`
  define the patterns. The pre-commit hook scans every added line and runs
  gitleaks on every commit; the pre-push hook repeats both over every commit a
  push would publish, including its message, author and committer, and scans
  each pushed annotated tag's message and tagger. Neither gitleaks scan
  has a bypass; `SKIP_PATTERN_SCAN=1` skips only the pattern scan. CI runs
  gitleaks on every push to `main` and every PR into it.
- **Local pattern lists** — names that must not be published, kept out of the
  repository in the gitignored `.githooks/*-patterns.local` lists, which the
  hooks read and refuse to commit. A repository can disregard a local identity
  pattern that is its own public identity by putting its exact text in
  `LOCAL_IDENTITY_IGNORE` in `.githooks/guard-config.sh`, in a reviewed commit;
  the secret-shaped list cannot be opted out of.
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

- **Gitleaks** — scans for accidental secret commits on every push to `main`
  and every PR into it.
- **Pattern sync test** — verifies the hooks' patterns in
  `.githooks/guard-config.sh` stay aligned with `.gitleaks.toml`.
- **Output-ignore check** — verifies every hydrated output, `config.env` and the
  local pattern lists are gitignored and untracked.
- **Guard tests** — `tests/test-git-guards.sh` and `tests/test-pre-push.sh`
  exercise both hooks against planted values, `tests/test-history-push.sh`
  pushes the whole history through the pre-push, as a fork's first push would,
  and `tests/test-output-ignore-check.sh` tests the output-ignore check itself.
- **ShellCheck** — static analysis of all `.sh`, `.sh.tmpl` and `.zsh` files and
  the git hooks at `--severity=warning` or above. Exclusions are centralised in
  `.shellcheckrc`.

## Dependency Pinning

- GitHub Actions use full commit SHAs (not tags) to prevent supply-chain attacks
  via tag mutation.
- Oh My Zsh, zsh-syntax-highlighting, and zsh-autosuggestions are cloned at
  pinned commits or tags.
- Homebrew install script is fetched at a pinned commit.
