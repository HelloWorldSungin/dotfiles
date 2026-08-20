#!/usr/bin/env bash
# Bootstrap script for skim-ub24-1 (Ubuntu 24.04.4 LTS VM with sudo and GitHub access)
# Safe and idempotent - can be re-run at any time to update or repair.

set -euo pipefail

DOTFILES="${HOME}/dotfiles"
NVIM_VERSION="v0.12.4"
LAZYGIT_VERSION="v0.44.1"
STARSHIP_VERSION="v1.22.1"
HERDR_VERSION="v0.8.0"
NODE_VERSION="v22.14.0"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
success() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
info() { printf '  \033[33m->\033[0m %s\n' "$*"; }

if [ "$(cd "$(dirname "$0")" && pwd)" != "$DOTFILES" ]; then
  echo "This script must be run from $DOTFILES:"
  echo "  git clone -b skim-ub24-1 https://github.com/HelloWorldSungin/dotfiles.git ~/dotfiles"
  echo "  bash ~/dotfiles/bootstrap-skim-ub24-1.sh"
  exit 1
fi

# Ensure user local bin exists and is on PATH
mkdir -p "${HOME}/.local/bin" "${HOME}/.config" "${HOME}/.npm-global/bin"
export PATH="${HOME}/.local/bin:${HOME}/.npm-global/bin:/usr/local/bin:${PATH}"

step "1/8 System packages via APT"
if command -v sudo >/dev/null 2>&1; then
  info "Updating apt package list..."
  sudo apt-get update -y || echo "  (Warning: some apt repos failed, continuing with available sources)"

  info "Installing core development tools..."
  sudo apt-get install -y \
    build-essential \
    git \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    curl \
    wget \
    jq \
    tar \
    unzip \
    htop \
    tree \
    ripgrep \
    fd-find \
    fzf \
    environment-modules \
    xauth \
    gawk \
    tcsh \
    debianutils || true

  # Ensure fallback clone of zsh plugins if not installed via apt
  mkdir -p "${HOME}/.zsh"
  if [ ! -d "${HOME}/.zsh/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${HOME}/.zsh/zsh-autosuggestions" 2>/dev/null || true
  fi
  if [ ! -d "${HOME}/.zsh/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${HOME}/.zsh/zsh-syntax-highlighting" 2>/dev/null || true
  fi

  # Ubuntu package name aliases
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    success "Linked fdfind -> /usr/local/bin/fd"
  fi
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    success "Linked batcat -> /usr/local/bin/bat"
  fi
else
  info "sudo not available, skipping apt installation."
fi

step "2/8 Modern Neovim (${NVIM_VERSION})"
INSTALLED_NVIM_VER=""
if command -v nvim >/dev/null 2>&1; then
  INSTALLED_NVIM_VER=$(nvim --version | head -n 1 | awk '{print $2}')
fi

if [[ "$INSTALLED_NVIM_VER" == "$NVIM_VERSION" || "$INSTALLED_NVIM_VER" == "${NVIM_VERSION#v}" ]]; then
  success "Neovim ${INSTALLED_NVIM_VER} is already installed."
else
  info "Downloading Neovim ${NVIM_VERSION} from GitHub Releases..."
  TMP_NVIM=$(mktemp -d)
  curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" -o "${TMP_NVIM}/nvim-linux-x86_64.tar.gz"
  sudo rm -rf /usr/local/nvim-linux-x86_64 /usr/local/nvim-linux64
  sudo tar -C /usr/local -xzf "${TMP_NVIM}/nvim-linux-x86_64.tar.gz"
  sudo ln -sf /usr/local/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  rm -rf "${TMP_NVIM}"
  success "Neovim ${NVIM_VERSION} installed to /usr/local/bin/nvim"
fi

step "3/8 Lazygit (${LAZYGIT_VERSION})"
if command -v lazygit >/dev/null 2>&1; then
  success "lazygit is already installed."
else
  info "Downloading Lazygit from GitHub Releases..."
  TMP_LG=$(mktemp -d)
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz" -o "${TMP_LG}/lazygit.tar.gz"
  tar -C "${TMP_LG}" -xzf "${TMP_LG}/lazygit.tar.gz"
  sudo install -m 755 "${TMP_LG}/lazygit" /usr/local/bin/lazygit
  rm -rf "${TMP_LG}"
  success "lazygit installed to /usr/local/bin/lazygit"
fi

step "4/8 Starship Prompt (${STARSHIP_VERSION})"
if command -v starship >/dev/null 2>&1; then
  success "starship is already installed."
else
  info "Downloading Starship from GitHub Releases..."
  TMP_SS=$(mktemp -d)
  curl -fsSL "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" -o "${TMP_SS}/starship.tar.gz"
  tar -C "${TMP_SS}" -xzf "${TMP_SS}/starship.tar.gz"
  sudo install -m 755 "${TMP_SS}/starship" /usr/local/bin/starship
  rm -rf "${TMP_SS}"
  success "starship installed to /usr/local/bin/starship"
fi

step "5/8 Herdr Session Layer (${HERDR_VERSION})"
if command -v herdr >/dev/null 2>&1; then
  success "herdr is already installed."
else
  info "Downloading Herdr from GitHub Releases..."
  TMP_HERDR=$(mktemp -d)
  if curl -fsSL "https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/herdr-linux-x86_64" -o "${TMP_HERDR}/herdr"; then
    sudo install -m 755 "${TMP_HERDR}/herdr" /usr/local/bin/herdr
    success "herdr installed to /usr/local/bin/herdr"
  else
    info "GitHub asset download failed; falling back to install script..."
    curl -fsSL https://herdr.dev/install.sh | sh || true
  fi
  rm -rf "${TMP_HERDR}"
fi

step "6/8 Node.js (${NODE_VERSION})"
if command -v node >/dev/null 2>&1; then
  success "Node.js $(node --version) is already installed."
else
  info "Downloading Node.js ${NODE_VERSION} from nodejs.org..."
  TMP_NODE=$(mktemp -d)
  if curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" -o "${TMP_NODE}/node.tar.xz"; then
    sudo mkdir -p /usr/local/lib/nodejs
    sudo rm -rf "/usr/local/lib/nodejs/node-${NODE_VERSION}-linux-x64"
    sudo tar -C /usr/local/lib/nodejs -xJf "${TMP_NODE}/node.tar.xz"
    sudo ln -sf "/usr/local/lib/nodejs/node-${NODE_VERSION}-linux-x64/bin/node" /usr/local/bin/node
    sudo ln -sf "/usr/local/lib/nodejs/node-${NODE_VERSION}-linux-x64/bin/npm" /usr/local/bin/npm
    sudo ln -sf "/usr/local/lib/nodejs/node-${NODE_VERSION}-linux-x64/bin/npx" /usr/local/bin/npx
    success "Node.js ${NODE_VERSION} installed to /usr/local/bin/node"
  else
    echo "  (Could not download Node.js directly; install via nvm or apt if needed)"
  fi
  rm -rf "${TMP_NODE}"
fi

step "7/8 Symlink Dotfiles & Shell Configuration (Bash & Zsh)"
# Neovim config
if [ -L "${HOME}/.config/nvim" ]; then
  success "~/.config/nvim symlink already in place."
else
  [ -d "${HOME}/.config/nvim" ] && mv "${HOME}/.config/nvim" "${HOME}/.config/nvim.backup.$(date +%s)"
  ln -sf "${DOTFILES}/config/nvim" "${HOME}/.config/nvim"
  success "Symlinked ~/.config/nvim -> ~/dotfiles/config/nvim"
fi

# Herdr config
mkdir -p "${HOME}/.config/herdr"
if [ -L "${HOME}/.config/herdr/config.toml" ]; then
  success "~/.config/herdr/config.toml symlink already in place."
else
  ln -sf "${DOTFILES}/config/herdr/config.toml" "${HOME}/.config/herdr/config.toml"
  success "Symlinked ~/.config/herdr/config.toml -> ~/dotfiles/config/herdr/config.toml"
fi

# Starship config
if [ -L "${HOME}/.config/starship.toml" ]; then
  success "~/.config/starship.toml symlink already in place."
else
  ln -sf "${DOTFILES}/config/starship/starship.toml" "${HOME}/.config/starship.toml"
  success "Symlinked ~/.config/starship.toml -> ~/dotfiles/config/starship/starship.toml"
fi

# Cleanly write ~/.bashrc_custom
cat << 'EOF' > "${HOME}/.bashrc_custom"
# >>> Sungin Dotfiles Environment >>>
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
export EDITOR="nvim"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"

alias v="nvim"
alias lg="lazygit"
alias g="git"
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias gpl="git pull --rebase"
alias gp="git push"
alias gpf="git push --force-with-lease"
alias ga="git add"
alias gc="git commit"
alias gco="git checkout"
alias gb="git branch"
alias gsw="git switch"
alias gcl="git clone --recurse-submodules"
alias gsu="git submodule update --init --recursive"

# ClearCase aliases
alias ct="cleartool"
alias cco="cleartool checkout -nc"
alias cci="cleartool checkin -nc"
alias cunco="cleartool uncheckout -rm"
alias clsco="cleartool lsco -cview -me"
alias cpwv="cleartool pwv"
alias cdiff="cleartool diff -pred"
alias chist="cleartool lshistory"
alias cdesc="cleartool describe"

# Add Enterprise EDA, LSF, Gemini, and ClearCase tools to PATH
for pdir in \
  /s/gemini/tools/scripts \
  /s/gemini/tools/bin \
  /s/gemini/tools/lsf/10.1.x/10.1/linux2.6-glibc2.3-x86_64/bin \
  /s/gemini/tools/lsf/10.1/linux2.6-glibc2.3-x86_64/bin \
  /s/gemini/tools/lsf/bin \
  /opt/ibm/lsf/bin \
  /usr/atria/bin \
  /opt/rational/clearcase/bin \
  /var/adm/rational/clearcase/bin; do
  [ -d "$pdir" ] && export PATH="$pdir:$PATH"
done

# Initialize Environment Modules (module load ...)
if [ -f /etc/profile.d/modules.sh ]; then
  source /etc/profile.d/modules.sh
elif [ -f /usr/share/modules/init/bash ] && [ -n "$BASH_VERSION" ]; then
  source /usr/share/modules/init/bash
elif [ -f /usr/share/modules/init/zsh ] && [ -n "$ZSH_VERSION" ]; then
  source /usr/share/modules/init/zsh
fi

# Source LSF cluster configuration if available
for lsf_conf in \
  /s/gemini/tools/lsf/conf/profile.lsf \
  /s/gemini/tools/lsf/10.1.x/conf/profile.lsf \
  /s/gemini/tools/lsf/10.1/conf/profile.lsf; do
  if [ -f "$lsf_conf" ]; then
    source "$lsf_conf"
    break
  fi
done

# Starship Prompt initialization
if command -v starship >/dev/null 2>&1; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(starship init zsh)"
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(starship init bash)"
  fi
fi

# Auto-cd on new workspace creation, but preserve active workspace directory in existing spaces/panes
WORK_DIR="/s/mrcy/ems/users/skim"
_CURRENT_SPACE="${HERDR_SPACE:-${HERDR_WORKSPACE:-${HERDR_SESSION:-}}}"
if [ -d "$WORK_DIR" ]; then
  if [ -n "$_CURRENT_SPACE" ]; then
    if [ "${_HERDR_INITIALIZED_SPACE:-}" != "$_CURRENT_SPACE" ]; then
      export _HERDR_INITIALIZED_SPACE="$_CURRENT_SPACE"
      cd "$WORK_DIR"
    fi
  elif [ "$PWD" = "$HOME" ] || [ "$PWD" = "/" ]; then
    cd "$WORK_DIR"
  fi
fi

# Auto-launch Zsh for interactive terminals
if [ -t 1 ] && [ -n "$PS1" ] && [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then
  export SHELL="$(which zsh)"
  exec zsh -l
fi
# <<< Sungin Dotfiles Environment <<<
EOF
success "Configured ~/.bashrc_custom (with workspace auto-cd and Zsh auto-launch)"

# Cleanly write ~/.zshrc if writable
if [ -w "${HOME}" ] || [ -w "${HOME}/.zshrc" 2>/dev/null ]; then
cat << 'EOF' > "${HOME}/.zshrc"
# >>> Sungin Dotfiles Environment >>>
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
export EDITOR="nvim"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"

# Add Enterprise EDA, LSF, Gemini, and ClearCase tools to PATH
for pdir in \
  /s/gemini/tools/scripts \
  /s/gemini/tools/bin \
  /s/gemini/tools/lsf/10.1.x/10.1/linux2.6-glibc2.3-x86_64/bin \
  /s/gemini/tools/lsf/10.1/linux2.6-glibc2.3-x86_64/bin \
  /s/gemini/tools/lsf/bin \
  /opt/ibm/lsf/bin \
  /usr/atria/bin \
  /opt/rational/clearcase/bin \
  /var/adm/rational/clearcase/bin; do
  [ -d "$pdir" ] && export PATH="$pdir:$PATH"
done

# Initialize Environment Modules (module load ...)
if [ -f /etc/profile.d/modules.sh ]; then
  source /etc/profile.d/modules.sh
elif [ -f /usr/share/modules/init/zsh ] && [ -n "$ZSH_VERSION" ]; then
  source /usr/share/modules/init/zsh
elif [ -f /usr/share/modules/init/bash ] && [ -n "$BASH_VERSION" ]; then
  source /usr/share/modules/init/bash
fi

# Source LSF cluster configuration if available
for lsf_conf in \
  /s/gemini/tools/lsf/conf/profile.lsf \
  /s/gemini/tools/lsf/10.1.x/conf/profile.lsf \
  /s/gemini/tools/lsf/10.1/conf/profile.lsf; do
  if [ -f "$lsf_conf" ]; then
    source "$lsf_conf"
    break
  fi
done

alias v="nvim"
alias lg="lazygit"
alias g="git"
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias gpl="git pull --rebase"
alias gp="git push"
alias gpf="git push --force-with-lease"
alias ga="git add"
alias gc="git commit"
alias gco="git checkout"
alias gb="git branch"
alias gsw="git switch"
alias gcl="git clone --recurse-submodules"
alias gsu="git submodule update --init --recursive"

# ClearCase aliases
alias ct="cleartool"
alias cco="cleartool checkout -nc"
alias cci="cleartool checkin -nc"
alias cunco="cleartool uncheckout -rm"
alias clsco="cleartool lsco -cview -me"
alias cpwv="cleartool pwv"
alias cdiff="cleartool diff -pred"
alias chist="cleartool lshistory"
alias cdesc="cleartool describe"

# Zsh History configuration
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS HIST_FIND_NO_DUPS SHARE_HISTORY

# Load Zsh Autosuggestions
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Load Zsh Syntax Highlighting
if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Keybindings: Accept ghost-text autosuggestions with Ctrl-F or Ctrl-A
bindkey '^f' autosuggest-accept 2>/dev/null || true
bindkey '^a' autosuggest-accept 2>/dev/null || true

# Starship Prompt initialization
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Auto-cd on new workspace creation, but preserve active workspace directory in existing spaces/panes
WORK_DIR="/s/mrcy/ems/users/skim"
_CURRENT_SPACE="${HERDR_SPACE:-${HERDR_WORKSPACE:-${HERDR_SESSION:-}}}"
if [ -d "$WORK_DIR" ]; then
  if [ -n "$_CURRENT_SPACE" ]; then
    if [ "${_HERDR_INITIALIZED_SPACE:-}" != "$_CURRENT_SPACE" ]; then
      export _HERDR_INITIALIZED_SPACE="$_CURRENT_SPACE"
      cd "$WORK_DIR"
    fi
  elif [ "$PWD" = "$HOME" ] || [ "$PWD" = "/" ]; then
    cd "$WORK_DIR"
  fi
fi
# <<< Sungin Dotfiles Environment <<<
EOF
success "Configured ~/.zshrc (with workspace auto-cd, autosuggestions, and syntax highlighting)"
fi

# Switch login shell to zsh if requested & available
ZSH_BIN="$(which zsh 2>/dev/null || echo "")"
if [ -n "$ZSH_BIN" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_BIN" ]; then
  if command -v sudo >/dev/null 2>&1; then
    grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$ZSH_BIN" "$USER" || true
    success "Set default login shell to zsh (${ZSH_BIN})"
  fi
fi

step "8/8 Pre-sync Neovim Plugins"
info "Syncing Neovim plugins headlessly (lazy.nvim)..."
nvim --headless "+Lazy! sync" +qa || true
success "Neovim plugins synchronized."

echo
printf "\033[1;32m🎉 Setup completed for skim-ub24-1!\033[0m\n"
echo "To apply changes to your current shell immediately, run:"
echo "  source ~/.bashrc_custom   # (if staying in Bash)"
echo "  exec zsh                  # (to switch to Zsh with Starship prompt)"
