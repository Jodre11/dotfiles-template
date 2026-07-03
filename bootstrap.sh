#!/usr/bin/env bash
# bootstrap.sh — idempotent setup for a fresh macOS machine
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/config.env" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env"
fi

DOTFILES_DIR="$HOME/dotfiles"
# Configure in config.env
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:youruser/dotfiles.git}"

# ---------- Xcode CLI tools ----------
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Press any key once the installer completes."
    read -r -n 1
fi

# ---------- Homebrew ----------
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/540da2ca91271886910572df3a50332540ca84e4/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ---------- Clone dotfiles ----------
if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# ---------- Activate in-repo git hooks ----------
# Repo-local on purpose: a global core.hooksPath would override hooks in every
# other repository on the machine (husky, lefthook, etc.).
git -C "$DOTFILES_DIR" config core.hooksPath .githooks

# ---------- Trust third-party taps ----------
# Homebrew is moving to require explicit trust for non-official taps
# (becomes default in 5.2.0 / 6.0.0). Trust the specific formulae we
# depend on so `brew bundle` does not silently skip them. Tap first so
# the formulae resolve; both `brew tap` and `brew trust` are idempotent.
# Guarded so older Homebrew without the `trust` subcommand still bootstraps.
if brew trust --help &>/dev/null; then
    echo "Trusting third-party tap formulae..."
    brew tap microsoft/mssql-release
    brew tap uw-labs/tap
    brew trust --formula \
        microsoft/mssql-release/msodbcsql18 \
        microsoft/mssql-release/mssql-tools18 \
        uw-labs/tap/strongbox
fi

# ---------- Brew bundle ----------
echo "Installing Homebrew packages..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

# ---------- Approve quarantined cask apps ----------
# macOS Sequoia blocks programmatic quarantine removal on /Applications.
# Opening from the CLI presents an approvable Gatekeeper dialogue (unlike
# Finder's dead-end "Not Opened" prompt).
echo "Opening quarantined apps for Gatekeeper approval..."
for app in /Applications/*.app; do
    [ -d "$app" ] || continue
    if xattr -p com.apple.quarantine "$app" &>/dev/null; then
        echo "  $(basename "$app")"
        open "$app"
    fi
done

# ---------- Hydrate templates ----------
if [[ -f "$DOTFILES_DIR/hydrate.sh" ]]; then
    echo "Hydrating templates..."
    bash "$DOTFILES_DIR/hydrate.sh"
fi

# ---------- Stow packages ----------
echo "Linking dotfiles..."
PACKAGES=(zsh starship git tmux ghostty hammerspoon gh karabiner editorconfig ssh vscode mcp firefox homebrew aws docker)
for pkg in "${PACKAGES[@]}"; do
    stow -v -t "$HOME" -d "$DOTFILES_DIR" "$pkg"
done

# ---------- Hammerspoon watchdog LaunchAgent ----------
WATCHDOG_PLIST="$HOME/Library/LaunchAgents/com.user.hammerspoon-watchdog.plist"
if [ -f "$WATCHDOG_PLIST" ] && ! launchctl list com.user.hammerspoon-watchdog &>/dev/null; then
    echo "Loading Hammerspoon watchdog LaunchAgent..."
    launchctl load "$WATCHDOG_PLIST"
fi

# ---------- Homebrew update check LaunchAgent ----------
BREW_CHECK_PLIST="$HOME/Library/LaunchAgents/com.user.brew-check-updates.plist"
if [ -f "$BREW_CHECK_PLIST" ] && ! launchctl list com.user.brew-check-updates &>/dev/null; then
    echo "Loading Homebrew update check LaunchAgent..."
    launchctl load "$BREW_CHECK_PLIST"
fi

# ---------- Oh My Zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/e64912e0c1eaa32181c3b5e5e4bf8042ecd0e8a7/tools/install.sh)" "" --unattended
fi

# ---------- zsh-syntax-highlighting (manual clone used by .zshrc) ----------
if [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    mkdir -p "$HOME/.zsh"
    git clone --branch 0.8.0 --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.zsh/zsh-syntax-highlighting"
fi

# ---------- zsh-autosuggestions (Oh My Zsh custom plugin) ----------
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone --branch v0.7.1 --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
fi

# ---------- Whisper model ----------
WHISPER_MODEL_DIR="$HOME/.local/share/whisper"
mkdir -p "$WHISPER_MODEL_DIR"
if [ ! -f "$WHISPER_MODEL_DIR/ggml-large-v3-turbo-q8_0.bin" ]; then
    echo "Downloading whisper large-v3-turbo-q8_0 model..."
    curl -L -o "$WHISPER_MODEL_DIR/ggml-large-v3-turbo-q8_0.bin" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin"
fi
if [ ! -f "$WHISPER_MODEL_DIR/ggml-silero-v6.2.0.bin" ]; then
    echo "Downloading Silero VAD model..."
    curl -L -o "$WHISPER_MODEL_DIR/ggml-silero-v6.2.0.bin" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-silero-v6.2.0.bin"
fi

# ---------- Dictation audio directory ----------
mkdir -p "$HOME/.local/share/dictation"

# ---------- Rust toolchain ----------
if ! command -v rustup &>/dev/null; then
    echo "Installing Rust toolchain via rustup..."
    RUSTUP_INIT="$(mktemp /tmp/rustup-init.XXXXXXXXXX)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$RUSTUP_INIT"
    chmod +x "$RUSTUP_INIT"
    sh "$RUSTUP_INIT" -y
    rm -f "$RUSTUP_INIT"
    . "$HOME/.cargo/env"
fi

# ---------- Rust components ----------
echo "Installing Rust components..."
rustup component add rust-analyzer

# ---------- .NET SDKs (via official dotnet-install.sh) ----------
# Installs both LTS and STS SDKs to ~/.dotnet using Microsoft's install script.
# The Homebrew dotnet-sdk-versions cask tap is unreliable for multi-version installs.
# See: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script
DOTNET_INSTALL_DIR="$HOME/.dotnet"
DOTNET_INSTALL_SCRIPT="/tmp/dotnet-install.sh"

if [ ! -f "$DOTNET_INSTALL_SCRIPT" ]; then
    echo "Downloading dotnet-install.sh..."
    curl -sSL https://dot.net/v1/dotnet-install.sh -o "$DOTNET_INSTALL_SCRIPT"
    chmod +x "$DOTNET_INSTALL_SCRIPT"
fi

# Install STS (latest) first so its dotnet binary is the primary one.
echo "Installing .NET SDK (STS channel)..."
"$DOTNET_INSTALL_SCRIPT" \
    --channel STS \
    --install-dir "$DOTNET_INSTALL_DIR" \
    --no-path

# Install LTS alongside, keeping the STS dotnet binary.
echo "Installing .NET SDK (LTS channel)..."
"$DOTNET_INSTALL_SCRIPT" \
    --channel LTS \
    --install-dir "$DOTNET_INSTALL_DIR" \
    --no-path \
    --skip-non-versioned-files

rm -f "$DOTNET_INSTALL_SCRIPT"

# ---------- .NET global tools ----------
export DOTNET_ROOT="$DOTNET_INSTALL_DIR"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"

# Default .NET tools — override in config.env via DOTNET_TOOLS array
if [[ ${#DOTNET_TOOLS[@]} -eq 0 ]]; then
    DOTNET_TOOLS=(
        "aspire.cli"
        "coverlet.console"
        "csharp-ls"
        "dotnet-coverage"
        "dotnet-reportgenerator-globaltool"
        "dotnet-svcutil"
        "jetbrains.resharper.globaltools"
    )
fi
for tool in "${DOTNET_TOOLS[@]}"; do
    if ! dotnet tool list -g | grep -qi "$tool"; then
        echo "Installing .NET tool: $tool"
        dotnet tool install -g "$tool" || true
    fi
done

# ---------- npm global tools (LSP servers) ----------
NPM_GLOBAL_TOOLS=(
    "intelephense"
    "pyright"
    "typescript"
    "typescript-language-server"
)
echo "Installing npm global tools..."
npm install -g "${NPM_GLOBAL_TOOLS[@]}"

# ---------- pipx tools ----------
if ! pipx list | grep -q "it2"; then
    echo "Installing it2 (iTerm2 shell integration)..."
    pipx install it2
fi

# ---------- Terraform via tenv ----------
# tenv (installed by brew bundle) manages Terraform versions and provides the
# `terraform` shim. Track latest-stable so a fresh machine is current; re-running
# bumps to the newest GA. Both subcommands are idempotent.
if command -v tenv &>/dev/null; then
    echo "Installing latest-stable Terraform via tenv..."
    tenv tf install latest-stable
    tenv tf use latest-stable
fi

# ---------- Claude Code settings ----------
CLAUDE_SETTINGS_DIR="$HOME/.claude"
# Configure in config.env
CLAUDE_SETTINGS_REPO="${CLAUDE_SETTINGS_REPO:-git@github.com:youruser/claude-settings.git}"
if [ ! -d "$CLAUDE_SETTINGS_DIR/.git" ]; then
    echo "Cloning claude-settings..."
    if [ -d "$CLAUDE_SETTINGS_DIR" ]; then
        mv "$CLAUDE_SETTINGS_DIR" "${CLAUDE_SETTINGS_DIR}.bak"
    fi
    git clone "$CLAUDE_SETTINGS_REPO" "$CLAUDE_SETTINGS_DIR"
fi

echo "Running Claude Code platform setup..."
bash "$CLAUDE_SETTINGS_DIR/scripts/setup-platform.sh"

# ---------- Chrome (dev/Playwright hardening) ----------
echo "Applying Chrome hardening policies..."
bash "$DOTFILES_DIR/chrome/setup-chrome.sh"

# ---------- Firefox (arkenfox) ----------
echo ""
echo "Note: Firefox hardening setup requires Firefox to be closed."
echo "Run manually after bootstrap: ~/.config/firefox/setup.sh"

# ---------- Done ----------
echo ""
echo "Bootstrap complete. Open a new terminal to pick up changes."
echo ""
echo "Manual steps remaining:"
echo "  1. Set up Bitwarden Desktop (SSH agent, Touch ID unlock, login item)"
echo "  2. Grant accessibility permissions to Karabiner-Elements and Hammerspoon"
echo "  3. Store secrets:"
echo "     envchain --set <namespace> <PAT_NAME>  # if using envchain for NuGet"
echo "     mkdir -p ~/.config/datadog && chmod 700 ~/.config/datadog"
echo "     echo 'DD_API_KEY=...\nDD_APP_KEY=...' > ~/.config/datadog/env && chmod 600 ~/.config/datadog/env"
echo "  4. Verify ~/.claudeenv (stowed from zsh package) has correct Bedrock ARNs"
echo "  5. Close Firefox and run: ~/.config/firefox/setup.sh"
