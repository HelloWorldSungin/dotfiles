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

- **inputs**: where packages come from - `nixpkgs` pinned to the `nixos-26.05`
  release branch, and `home-manager` matching it. Pinning means a rebuild
  next month installs the same versions as today. Updating is an explicit
  act: `nix flake update` rewrites `flake.lock` (commit that file), and the
  audited revisions and package versions in `config/dev-tools-versions.sh` have
  to be refreshed in the same change, or `dev-tools-check-updates` reports the
  disagreement - see [dev-tool-versions.md](dev-tool-versions.md).
- **outputs**: named machine configurations. `homeConfigurations."sungin@ct110"`
  is the only one now; a Mac target joins later in the same file.

### home/dev-tools.nix

Every developer-tool derivation the repository packages itself - the pin and
closure-manifest artifacts, the read-only checker, the pinned installer, the
`cspend` wrapper, the Codex context-window activation helper, and the guarded
updater - is defined here once and exported through the `devTools` module
argument. `home/common.nix` and `home/sungin-ct110.nix` consume those exports,
so a change to a runtime closure or an exported path cannot ship two different
binaries to the same host.

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
nix flake update         # bump pinned inputs (refresh the pin record, then rebuild)
nix search nixpkgs foo   # find a package name
home-manager generations # list previous environments...
# ...and every generation is rollback-able if a rebuild goes wrong
```

## Why harness CLIs are NOT in Nix

Fast-moving agent harness CLIs release frequently and nixpkgs versions lag.
`bootstrap.sh` delegates their install-if-absent path to
`bin/dev-tools-install-pinned`, which installs exact npm versions with registry
integrity verification or exact publisher assets with recorded checksums into
user-writable prefixes (`~/.local/bin`, `~/.npm-global/bin`). The central record
and known upstream limitations are documented in `docs/dev-tool-versions.md`.
