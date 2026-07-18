#!/usr/bin/env bash
# Bring a fresh Linux machine/user to the full environment. Idempotent -
# safe to re-run any time. This script IS the reproducibility guarantee:
# if it can't rebuild everything from scratch, that's a bug.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
FLAKE_TARGET="sungin@ct110"

if [ "$(cd "$(dirname "$0")" && pwd)" != "$DOTFILES" ]; then
  echo "This repo must live at ~/dotfiles (scripts and symlinks assume it):"
  echo "  git clone git@github.com:HelloWorldSungin/dotfiles.git ~/dotfiles"
  exit 1
fi

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "1/5 Nix (Determinate, multi-user daemon)"
if ! command -v nix >/dev/null 2>&1; then
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # Installed but not in this shell's env yet
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  else
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi
nix --version

step "2/5 home-manager switch (packages, zsh, nvim, symlinks)"
if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "$DOTFILES#$FLAKE_TARGET"
else
  nix run github:nix-community/home-manager/release-25.11 -- \
    switch --flake "$DOTFILES#$FLAKE_TARGET"
fi

# Everything below installs into user-writable prefixes; make sure the
# freshly-configured paths work in this very shell too.
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

step "3/5 zsh as login shell"
ZSH_PATH="$HOME/.nix-profile/bin/zsh"
if [ -x "$ZSH_PATH" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  sudo chsh -s "$ZSH_PATH" "$USER"
fi

step "4/5 herdr (session layer)"
command -v herdr >/dev/null 2>&1 || curl -fsSL https://herdr.dev/install.sh | sh
herdr --version

step "5/5 agent harnesses (fast-moving CLIs - official installers, not Nix)"
command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
command -v codex >/dev/null 2>&1 || npm install -g @openai/codex
command -v opencode >/dev/null 2>&1 || curl -fsSL https://opencode.ai/install | bash
# opencode's installer only patches .bashrc; we run zsh - expose it on the
# PATH we actually use instead.
[ -x "$HOME/.opencode/bin/opencode" ] && ln -sf "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
command -v pi >/dev/null 2>&1 || npm install -g @mariozechner/pi-coding-agent

step "6/6 agent toolchain (Kun Chen stack)"
command -v treehouse >/dev/null 2>&1 || curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh
command -v no-mistakes >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
command -v gnhf >/dev/null 2>&1 || npm install -g gnhf
command -v gh-axi >/dev/null 2>&1 || npm install -g gh-axi
command -v tasks-axi >/dev/null 2>&1 || npm install -g tasks-axi
command -v quota-axi >/dev/null 2>&1 || npm install -g quota-axi
command -v chrome-devtools-axi >/dev/null 2>&1 || npm install -g chrome-devtools-axi
# firstmate is distributed as a repo you run agents inside, not a binary
[ -d "$HOME/firstmate" ] || git clone https://github.com/kunchenguid/firstmate.git "$HOME/firstmate"

echo
echo "Done. Open a NEW login shell (or 'exec zsh'), then log in once to each"
echo "harness (claude / codex / opencode / pi) and 'gh auth login'."
echo "After gh is authed: 'gh-axi setup hooks'. See docs/agents.md."
