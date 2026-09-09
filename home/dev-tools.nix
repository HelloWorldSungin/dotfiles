# Single owner of every repository-packaged developer-tool derivation.
#
# `home/common.nix` imports this module and both it and `home/sungin-ct110.nix`
# consume the exported set through the `devTools` module argument, so the
# checker the operator runs from PATH, the one the weekly timer runs, the one
# the login shell runs, and the one on the guarded updater's runtime PATH are
# the same store path by construction rather than by two texts happening to
# agree. `tests/dev-tools-nix-packaging.test.sh` evaluates that invariant.
{ pkgs, ... }:

let
  lib = pkgs.lib;

  # One owner for every wrapper runtime input, keyed by the same nixpkgs
  # attribute names `config/dev-tools-versions.sh` pins, and split by where the
  # audit may read the installed version from. `closureOnlyInputs` reach the
  # operator only through a wrapper's own PATH, so the generated manifest binds
  # each of them to its exact store path and the checker measures them there.
  # `userEnvInputs` are also in the user environment, so the command the operator
  # runs is the pinned one and keeps its ambient measurement - they are wrapper
  # inputs too, but they are deliberately not in the manifest.
  closureOnlyInputs = {
    inherit (pkgs) coreutils curl diffutils gawk gnugrep gnused gnutar gzip;
  };
  userEnvInputs = {
    inherit (pkgs) git jq;
    nodejs_22 = pkgs.nodejs_22;
  };
  runtimeInputsByName = closureOnlyInputs // userEnvInputs;
  pick = names: map (name: runtimeInputsByName.${name}) names;

  closureManifest = pkgs.writeText "dev-tools-closure.json" (builtins.toJSON
    (lib.mapAttrsToList
      (name: package: { inherit name; version = lib.getVersion package; store_path = package.outPath; })
      closureOnlyInputs));

  pins = pkgs.writeText "dev-tools-versions.sh" (builtins.readFile ../config/dev-tools-versions.sh);
  flakeLock = pkgs.writeText "flake.lock" (builtins.readFile ../flake.lock);
  nvimPluginLock = pkgs.writeText "nvim-lazy-lock.json" (builtins.readFile ../config/nvim/lazy-lock.json);

  checker = pkgs.writeShellApplication {
    name = "dev-tools-check-updates";
    text = ''
      export DEV_TOOLS_PINS_FILE=${pins}
      export DEV_TOOLS_FLAKE_LOCK_FILE=${flakeLock}
      export DEV_TOOLS_NVIM_LOCK_FILE=${nvimPluginLock}
      export DEV_TOOLS_CLOSURE_FILE=${closureManifest}
      ${builtins.readFile ../bin/dev-tools-check-updates}
    '';
    bashOptions = [ ]; # The checker deliberately handles source failures itself.
    runtimeInputs = pick [ "coreutils" "curl" "gawk" "git" "gnugrep" "gnused" "jq" "nodejs_22" ];
  };

  pinnedInstaller = pkgs.writeShellApplication {
    name = "dev-tools-install-pinned";
    text = ''
      export DEV_TOOLS_PINS_FILE=${pins}
      ${builtins.readFile ../bin/dev-tools-install-pinned}
    '';
    runtimeInputs = pick [ "coreutils" "curl" "gawk" "git" "gnugrep" "gnutar" "gzip" "jq" "nodejs_22" ];
  };

  claudeSpendPinned = pkgs.writeShellApplication {
    name = "claude-spend-pinned";
    text = ''
      export DEV_TOOLS_PINS_FILE=${pins}
      ${builtins.readFile ../bin/claude-spend-pinned}
    '';
    runtimeInputs = pick [ "coreutils" "gnugrep" "nodejs_22" ];
  };

  codexSetContextWindow = pkgs.writeShellApplication {
    name = "codex-set-context-window";
    text = builtins.readFile ../bin/codex-set-context-window;
    runtimeInputs = pick [ "coreutils" "diffutils" "gawk" ];
  };

  # Guarded, opt-in companion to the checker. Installed on PATH but deliberately
  # NOT given a timer: it only ever runs when the captain invokes it. Every
  # command it shells out to is declared here - awk parses `git ls-remote`, grep
  # validates the commit, version, and integrity pins, sed prints the operator
  # contract, and tar reads an operator-supplied artifact's own manifest - so a
  # stripped ambient PATH cannot turn a well-formed pin into a refusal. The
  # checker is included so its detection delegation resolves.
  applyUpdates = pkgs.writeShellApplication {
    name = "dev-tools-apply-updates";
    text = ''
      export DEV_TOOLS_PINS_FILE=${pins}
      ${builtins.readFile ../bin/dev-tools-apply-updates}
    '';
    bashOptions = [ ]; # Applies each tier independently and handles failures itself.
    runtimeInputs = pick [ "coreutils" "gawk" "git" "gnugrep" "gnused" "gnutar" "gzip" "jq" "nodejs_22" ]
      ++ [ checker ];
  };
in
{
  _module.args.devTools = {
    inherit
      closureOnlyInputs userEnvInputs closureManifest pins flakeLock nvimPluginLock
      checker pinnedInstaller claudeSpendPinned codexSetContextWindow applyUpdates;
  };
}
