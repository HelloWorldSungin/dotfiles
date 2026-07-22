{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  imports = [ ./common.nix ];

  home.username = "sunginkim";
  home.homeDirectory = "/Users/sunginkim";

  # Mac client terminal config (WezTerm)
  xdg.configFile."wezterm".source = link "config/wezterm";

  # baby-menu config symlinks
  home.file.".baby-menu/agents.json".source = link "config/baby-menu/agents.json";
  home.file.".baby-menu/preferences.json".source = link "config/baby-menu/preferences.json";

  home.sessionPath = [
    "$HOME/.bun/bin"
    "$HOME/.antigravity/antigravity/bin"
    "$HOME/.antigravity-ide/antigravity-ide/bin"
    "$HOME/.mavis/bin"
    "/Applications/WezTerm.app/Contents/MacOS"
    "$HOME/.nvm/versions/node/v20.20.2/bin"
  ];

  programs.zsh = {
    envExtra = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
    '';
    shellAliases = {
      shot = "~/dotfiles/bin/shot2ct110";
      anti-g = "/Applications/Antigravity\\ IDE.app/Contents/Resources/app/bin/antigravity-ide";
    };
    initContent = ''
      # Bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      # Lazy-loaded NVM
      export NVM_DIR="$HOME/.nvm"
      nvm() {
        unset -f nvm
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm "$@"
      }

      # Oh My Pi completions
      _omp_cache="$HOME/.cache/omp-completions.zsh"
      if [[ ! -s "$_omp_cache" || "$(command -v omp)" -nt "$_omp_cache" ]]; then
        mkdir -p "$HOME/.cache" && omp completions zsh >| "$_omp_cache" 2>/dev/null || true
      fi
      [ -s "$_omp_cache" ] && source "$_omp_cache"
    '';
  };
}
