#!/usr/bin/env bash
# Apply the current Nix config. Run after ANY change to flake.nix or
# home/*.nix (config/ changes need no rebuild - they're live symlinks).
set -euo pipefail
cd "$HOME/dotfiles"

if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake ".#sungin@ct110"
else
  nix run github:nix-community/home-manager/release-25.11 -- \
    switch --flake ".#sungin@ct110"
fi
