#!/usr/bin/env bash
# Bring a fresh machine/user to the full environment. Idempotent -
# safe to re-run any time. This script IS the reproducibility guarantee:
# if it can't rebuild everything from scratch, that's a bug.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
IS_DARWIN=false
if [ "$(uname -s)" = "Darwin" ]; then
  IS_DARWIN=true
  FLAKE_TARGET="sunginkim@macbook"
else
  FLAKE_TARGET="sungin@ct110"
fi

if [ "$(cd "$(dirname "$0")" && pwd)" != "$DOTFILES" ]; then
  echo "This repo must live at ~/dotfiles (scripts and symlinks assume it):"
  echo "  git clone https://github.com/HelloWorldSungin/dotfiles.git ~/dotfiles"
  exit 1
fi

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

install_if_missing() {
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "  ✓ $name is already installed, skipping."
  else
    echo "  -> Installing $name..."
    "$@"
  fi
}

step "1/6 Nix (Determinate, multi-user daemon)"
if command -v nix >/dev/null 2>&1; then
  echo "  ✓ Nix is already installed."
elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  echo "  -> Sourcing existing Nix daemon profile..."
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  echo "  -> Installing Nix via Determinate Systems installer..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
nix --version

step "2/6 home-manager switch (packages, zsh, nvim, symlinks)"
if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "$DOTFILES#$FLAKE_TARGET" -b backup
else
  nix run github:nix-community/home-manager/release-25.11 -- \
    switch --flake "$DOTFILES#$FLAKE_TARGET" -b backup
fi

# Everything below installs into user-writable prefixes; make sure the
# freshly-configured paths work in this very shell too.
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$HOME/.npm-global/bin"

step "3/6 zsh as login shell"
ZSH_PATH="$HOME/.nix-profile/bin/zsh"
CURRENT_SHELL=""
if $IS_DARWIN; then
  CURRENT_SHELL=$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}' || echo "$SHELL")
else
  if command -v getent >/dev/null 2>&1; then
    CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
  else
    CURRENT_SHELL="$SHELL"
  fi
fi

if [ "$CURRENT_SHELL" = "$ZSH_PATH" ] || [ "$CURRENT_SHELL" = "/bin/zsh" ]; then
  echo "  ✓ zsh is already the login shell."
elif [ -x "$ZSH_PATH" ]; then
  if sudo -n true 2>/dev/null; then
    grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$ZSH_PATH" "$USER"
  else
    echo "  login shell not set and no sudo — run once as root:"
    echo "    grep -qxF '$ZSH_PATH' /etc/shells || echo '$ZSH_PATH' >> /etc/shells"
    echo "    chsh -s '$ZSH_PATH' $USER"
  fi
fi

step "4/6 herdr (session layer)"
if command -v herdr >/dev/null 2>&1; then
  echo "  ✓ herdr is already installed."
else
  echo "  -> Installing herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh
fi
command -v herdr >/dev/null 2>&1 && herdr --version || true

step "5/6 agent harnesses (fast-moving CLIs)"
install_if_missing claude bash -c "curl -fsSL https://claude.ai/install.sh | bash"
install_if_missing codex npm install -g @openai/codex
install_if_missing opencode bash -c "curl -fsSL https://opencode.ai/install | bash"
[ -x "$HOME/.opencode/bin/opencode" ] && ln -sf "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
install_if_missing pi npm install -g @mariozechner/pi-coding-agent
install_if_missing agy bash -c "curl -fsSL https://antigravity.google/cli/install.sh | bash"
install_if_missing cursor-agent bash -c "curl https://cursor.com/install -fsS | bash"

step "6/6 agent toolchain (Kun Chen stack)"
install_if_missing treehouse bash -c "curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh"
install_if_missing no-mistakes bash -c "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh"
install_if_missing gnhf npm install -g gnhf
install_if_missing gh-axi npm install -g gh-axi
install_if_missing tasks-axi npm install -g tasks-axi
install_if_missing quota-axi npm install -g quota-axi
install_if_missing chrome-devtools-axi npm install -g chrome-devtools-axi

if [ -d "$HOME/firstmate" ]; then
  echo "  ✓ firstmate repository is already cloned."
else
  echo "  -> Cloning firstmate repository..."
  git clone https://github.com/kunchenguid/firstmate.git "$HOME/firstmate"
fi

if [ -d "$HOME/baby-menu" ]; then
  echo "  ✓ baby-menu repository is already cloned."
else
  echo "  -> Cloning baby-menu repository..."
  git clone https://github.com/kunchenguid/baby-menu.git "$HOME/baby-menu"
fi

echo
echo "Done. Open a NEW login shell (or 'exec zsh'), then log in once to each"
echo "harness (claude / codex / opencode / pi / agy / cursor-agent) and 'gh auth login'."
echo "After gh is authed: 'gh-axi setup hooks'. See docs/agents.md."
