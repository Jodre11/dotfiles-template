# Brewfile — review and remove what you don't need.
# Regenerate after changes: brew bundle dump --file=~/dotfiles/Brewfile --force

# --- Taps ---
tap "microsoft/mssql-release"
tap "uw-labs/tap"

# --- Core tools ---
brew "bash"
brew "cmake"
brew "cmake-docs"
brew "fd"
brew "fzf"
brew "jq"                       # JSON processor (used by Claude Code hooks)
brew "ninja"
brew "pipx"
brew "stow"                     # Symlink manager for dotfiles
brew "wget"
brew "yq"
brew "zsh"

# --- Version control ---
brew "gh"                       # GitHub CLI
brew "git-delta"                # Better git diffs
brew "git-filter-repo"          # Git history rewriting
brew "gitleaks"                 # Secret scanning

# --- Security ---
brew "age"                      # Modern file encryption
brew "envchain"                 # Keychain-backed env vars
brew "uw-labs/tap/strongbox"    # Transparent git encryption

# --- Cloud and infrastructure ---
brew "awscli"
brew "azure-cli"
brew "terraform"
brew "tflint"

# --- Languages and runtimes ---
brew "go"
brew "llvm"
brew "lld"
brew "node"
brew "python@3.14"
brew "python-tk@3.14"

# --- Development tools ---
brew "act"                      # Local GitHub Actions runner
brew "actionlint"               # GitHub Actions linter
brew "bat"                      # Better cat
brew "shellcheck"               # Shell script linter
brew "starship"                 # Cross-shell prompt
brew "thefuck"                  # Command correction
brew "tmux"

# --- Code review tooling ---
brew "ruff"                     # Python linter (used by code-review:ruff-reviewer)
brew "trivy"                    # IaC security scanner (used by code-review:trivy-reviewer)

# --- Language servers ---
brew "jdtls"                    # Java
brew "kotlin-language-server"
brew "lua-language-server"

# --- Data and CLI tools ---
brew "ddgr"                     # DuckDuckGo CLI (used by web-search skill)
brew "pandoc"                   # Document converter (used by md2clip)
brew "potrace"
brew "librsvg"

# --- Media ---
brew "ffmpeg"
brew "sox"                      # Audio recording (used by dictation)
brew "whisper-cpp"              # Speech-to-text

# --- Networking ---
brew "bitwarden-cli"
brew "mosh"
brew "tailscale", restart_service: :changed

# --- Databases ---
brew "libiodbc"
brew "microsoft/mssql-release/msodbcsql18"
brew "microsoft/mssql-release/mssql-tools18"

# --- Cask apps ---
cask "bitwarden"
cask "docker-desktop"
cask "dotnet-sdk"
cask "dotnet-sdk@8"
cask "firefox"
cask "font-fira-code-nerd-font"
cask "font-meslo-lg-nerd-font"
cask "ghostty"
cask "gitify"                   # GitHub notifications menubar app
cask "google-chrome"
cask "hammerspoon"
cask "inkscape"
cask "insomnia"
cask "jetbrains-toolbox"
cask "karabiner-elements"
cask "macfuse"
cask "monitorcontrol"
cask "odbc-manager"
cask "termius"
cask "visual-studio-code"

# --- VS Code extensions ---
vscode "amazonwebservices.aws-toolkit-vscode"
vscode "eamodio.gitlens"
vscode "github.copilot-chat"
vscode "localstack.localstack"
vscode "ms-azuretools.vscode-containers"
vscode "ms-mssql.data-workspace-vscode"
vscode "ms-mssql.mssql"
vscode "ms-mssql.sql-bindings-vscode"
vscode "ms-mssql.sql-database-projects-vscode"
vscode "ms-vscode-remote.remote-containers"
vscode "ms-vscode-remote.remote-ssh"
vscode "ms-vscode-remote.remote-ssh-edit"
vscode "ms-vscode.remote-explorer"

# --- Go tools ---
go "github.com/golangci/golangci-lint/v2/cmd/golangci-lint"
go "golang.org/x/tools/gopls"

# --- Cargo tools ---
cargo "jiggy"
