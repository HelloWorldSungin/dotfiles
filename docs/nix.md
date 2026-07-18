# How the Nix layer works

## Mental model

Nix here is doing one job: **making the environment declarative**. Instead of
running `apt install ripgrep` and forgetting you did, you write `ripgrep` in
a list, run `rebuild`, and Nix makes the system match the list. Delete the
line, rebuild, and it's gone. The repo is the source of truth; the machine
is a cache.

Two components:

- **Nix** (installed by the Determinate installer, system-wide daemon):
  the package manager itself. Packages live in `/nix/store/...` and never
  conflict with Ubuntu's apt packages.
- **home-manager**: a Nix tool that manages *your user's* environment -
  packages on your PATH, your zsh config, your symlinks. It never touches
  the OS, other users, or root. That's why this setup can coexist with
  everything else running on CT110.

## The files

### flake.nix

The entry point. It declares:

- **inputs**: where packages come from - `nixpkgs` pinned to the `nixos-25.11`
  release branch, and `home-manager` matching it. Pinning means a rebuild
  next month installs the same versions as today. Updating is an explicit
  act: `nix flake update` (which rewrites `flake.lock` - commit that file).
- **outputs**: named machine configurations. `homeConfigurations."sungin@ct110"`
  is the only one now; a Mac target joins later in the same file.

### home/sungin-ct110.nix

The actual environment description. Reading it top to bottom IS the
documentation of what's installed. Key ideas:

- `home.packages = [ ... ]` - everything on your PATH. To add a tool, find
  its attribute name at https://search.nixos.org/packages and add it here.
- `programs.zsh = { ... }` - home-manager writes ~/.zshrc for you from this.
  Same for starship, fzf, git. You never edit those rc files by hand.
- `mkOutOfStoreSymlink` (the `link` helper at the top) - the important
  trick. Normal home-manager files are read-only copies in /nix/store.
  Configs we want to edit live (nvim, herdr) are instead symlinked back to
  `~/dotfiles/config/...`, so they're editable AND version-controlled, and
  need no rebuild to take effect.
- `home.stateVersion` - a compatibility marker. Set once, never change it.

## Commands you'll actually use

```sh
rebuild                  # alias for ./rebuild.sh - apply config changes
nix flake update         # bump pinned package versions (then rebuild)
nix search nixpkgs foo   # find a package name
home-manager generations # list previous environments...
# ...and every generation is rollback-able if a rebuild goes wrong
```

## Why harness CLIs are NOT in Nix

claude/codex/opencode self-update and release weekly; nixpkgs versions lag.
They're installed by `bootstrap.sh` via their official installers into
user-writable prefixes (`~/.local/bin`, `~/.npm-global/bin`). The *decision*
is still recorded in the repo - the script is the manifest.
