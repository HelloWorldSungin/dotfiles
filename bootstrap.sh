#!/usr/bin/env bash
# Bring a fresh machine/user to the full environment. Idempotent -
# safe to re-run any time. This script IS the reproducibility guarantee:
# if it can't rebuild everything from scratch, that's a bug.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
PINS_FILE="$DOTFILES/config/dev-tools-versions.sh"
PINNED_INSTALLER="$DOTFILES/bin/dev-tools-install-pinned"
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

# shellcheck source=config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS_FILE"

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

verify_sha256() {
  local file=$1 expected=$2 actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  else
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  fi
  [ "$actual" = "$expected" ]
}

step "1/6 Nix (Determinate, multi-user daemon)"
if command -v nix >/dev/null 2>&1; then
  echo "  ✓ Nix is already installed."
elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  echo "  -> Sourcing existing Nix daemon profile..."
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  echo "  -> Installing Nix via exact Determinate installer v${NIX_INSTALLER_VERSION}..."
  NIX_INSTALLER_TMP=$(mktemp "${TMPDIR:-/tmp}/nix-installer.XXXXXX")
  trap 'rm -f "$NIX_INSTALLER_TMP"' EXIT
  curl -fsSL "$NIX_INSTALLER_SCRIPT_URL" -o "$NIX_INSTALLER_TMP"
  verify_sha256 "$NIX_INSTALLER_TMP" "$NIX_INSTALLER_SCRIPT_SHA256" || {
    echo "Determinate installer checksum mismatch; refusing to execute it." >&2
    exit 1
  }
  sh "$NIX_INSTALLER_TMP" install --no-confirm
  rm -f "$NIX_INSTALLER_TMP"
  trap - EXIT
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
nix --version

step "2/6 home-manager switch (packages, zsh, nvim, symlinks)"
if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "$DOTFILES#$FLAKE_TARGET" -b backup
else
  nix run "github:nix-community/home-manager/${HOME_MANAGER_REV}" -- \
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

step "4/6 herdr (session layer, exact install-if-absent pin)"
"$PINNED_INSTALLER" --only herdr

step "5/6 agent harnesses (fast-moving CLIs)"
for tool in claude codex opencode pi agy; do
  "$PINNED_INSTALLER" --only "$tool"
done
echo "  - Skipping cursor-agent: upstream has no supported exact-version install."
echo "    The read-only checker reports its moving beta snapshot and drift."

step "6/6 agent toolchain (Kun Chen stack)"
for tool in treehouse no-mistakes gnhf gh-axi tasks-axi quota-axi chrome-devtools-axi lavish-axi firstmate baby-menu; do
  "$PINNED_INSTALLER" --only "$tool"
done

echo
echo "Done. Open a NEW login shell (or 'exec zsh'), then log in once to each"
echo "harness (claude / codex / opencode / pi / agy / cursor-agent) and 'gh auth login'."
echo "After gh is authed: 'gh-axi setup hooks'. See docs/agents.md."
