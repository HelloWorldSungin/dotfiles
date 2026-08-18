#!/usr/bin/env bash
# Apply the current Nix config for skim-ub24-1.
set -euo pipefail
cd "$HOME/dotfiles"

# Ensure nix is in PATH if installed on the system
if ! command -v nix >/dev/null 2>&1; then
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi

TARGET="${1:-skim@skim-ub24-1}"

if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake ".#$TARGET" -b backup
else
  nix run github:nix-community/home-manager/release-25.11 -- \
    switch --flake ".#$TARGET" -b backup
fi
