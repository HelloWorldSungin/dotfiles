#!/usr/bin/env bash
# Apply the current Nix config. Run after ANY change to flake.nix or
# home/*.nix (config/ changes need no rebuild - they're live symlinks).
set -euo pipefail
cd "$HOME/dotfiles"
# shellcheck source=config/dev-tools-versions.sh
# shellcheck disable=SC1091
source config/dev-tools-versions.sh

# Ensure nix is in PATH if installed on the system
if ! command -v nix >/dev/null 2>&1; then
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    TARGET="sunginkim@macbook"
  else
    TARGET="sungin@ct110"
  fi
fi

if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake ".#$TARGET" -b backup
else
  # Keep the fallback exact too. The central tool record matches flake.lock.
  nix run "github:nix-community/home-manager/$HOME_MANAGER_REV" -- \
    switch --flake ".#$TARGET" -b backup
fi
