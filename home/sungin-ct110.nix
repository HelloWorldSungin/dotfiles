{ config, pkgs, ... }:

let
  # All config symlinks point back into this repo clone, so editing
  # ~/.config/nvim (or letting a tool edit its own config) edits the repo.
  # That keeps every runtime change version-controlled - Kun's core trick.
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  home.username = "sungin";
  home.homeDirectory = "/home/sungin";
  home.stateVersion = "25.11"; # set once, never touch again

  programs.home-manager.enable = true; # gives us the `home-manager` CLI

  home.packages = with pkgs; [
    gh
    lazygit
    nodejs_22 # required by the axi tools (Node 20+) and npm-installed harnesses
    ripgrep
    fd
    fzf
    jq
    tree
    htop
    unzip
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    # npm's default global prefix would be the read-only /nix/store, so
    # global installs (codex, the axi tools) go to a user-writable prefix.
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin" # herdr and claude install here
  ];

  # ---------------------------------------------------------------- neovim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  # Plugin management is lazy.nvim (bootstrapped from config/nvim/init.lua),
  # not Nix - matches Kun's setup and keeps plugin iteration fast.
  xdg.configFile."nvim".source = link "config/nvim";

  # ------------------------------------------------- shared agent memory
  # One AGENTS.md is the single source of truth; every harness's global
  # memory location is a symlink to it. See docs/agents.md.
  home.file."AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".claude/CLAUDE.md".source = link "agents/AGENTS.md";
  home.file.".codex/AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".pi/agent/AGENTS.md".source = link "agents/AGENTS.md";

  # herdr reads ~/.config/herdr/config.toml; kept in-repo the same way.
  xdg.configFile."herdr/config.toml".source = link "config/herdr/config.toml";

  # ------------------------------------------------------------------ zsh
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;   # ghost-text completion from history
    syntaxHighlighting.enable = true;
    history.size = 50000;
    # .zshenv runs for EVERY zsh (including non-interactive `ssh ct110 cmd`),
    # so the nix profile is on PATH even without a login shell. The system
    # nix hook only covers bash on Ubuntu.
    envExtra = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
    '';
    initContent = ''
      # ctrl-f accepts the ghost-text suggestion (Kun's keybind)
      bindkey '^f' autosuggest-accept
    '';
    shellAliases = {
      g = "git";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline -20";
      v = "nvim";
      lg = "lazygit";
      rebuild = "~/dotfiles/rebuild.sh";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ------------------------------------------------------------------ git
  programs.git = {
    enable = true;
    userName = "Sungin Kim";
    userEmail = "sunginapp@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
