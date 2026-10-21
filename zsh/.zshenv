export LANG=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Machine-local secrets (API keys etc.) — never tracked in dotfiles.
[ -f "$HOME/.zshenv.local" ] && . "$HOME/.zshenv.local"

