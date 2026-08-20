{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  devToolsUpdateChecker = pkgs.writeShellApplication {
    name = "dev-tools-check-updates";
    text = builtins.readFile ../bin/dev-tools-check-updates;
    bashOptions = [ ]; # The checker deliberately handles source failures itself.
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      git
      gnugrep
      gnused
      jq
      nodejs_22
    ];
  };
in
{
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    devToolsUpdateChecker
    gh
    lazygit
    nodejs_22
    uv
    bats
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
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin"
  ];

  # ---------------------------------------------------------------- neovim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  xdg.configFile."nvim".source = link "config/nvim";

  # ------------------------------------------------- shared agent memory
  home.file."AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".claude/CLAUDE.md".source = link "agents/AGENTS.md";
  home.file.".codex/AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source = link "agents/AGENTS.md";
  home.file.".pi/agent/AGENTS.md".source = link "agents/AGENTS.md";

  # herdr configuration
  xdg.configFile."herdr/config.toml".source = link "config/herdr/config.toml";

  # --------------------------------------------------- vendored skills
  home.file.".claude/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";
  home.file.".pi/agent/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";
  home.file.".agents/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";

  # ------------------------------------------------ vendored pi extensions
  home.file.".pi/agent/extensions/fusion-harness".source = link "pi/extensions/fusion-harness";

  # ------------------------------------------------------------------ zsh
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 50000;
    initContent = ''
      # Accept ghost-text autosuggestions with Ctrl-F or Ctrl-A
      bindkey '^f' autosuggest-accept
      bindkey '^a' autosuggest-accept

      # Source local uncommitted secrets / custom overrides if present
      if [[ -f "$HOME/.zshrc.local" ]]; then
        source "$HOME/.zshrc.local"
      fi

      # Reset terminal mouse tracking mode on return to prompt (prevents ;53M scroll leaks)
      _reset_mouse_tracking() {
        printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l'
      }
      autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _reset_mouse_tracking 2>/dev/null || true

      # Auto-cd on new workspace creation, but preserve active workspace directory in existing spaces/panes
      WORK_DIR="/s/mrcy/ems/users/skim"
      _CURRENT_SPACE="${HERDR_SPACE:-${HERDR_WORKSPACE:-${HERDR_SESSION:-}}}"
      if [[ -d "$WORK_DIR" ]]; then
        if [[ -n "$_CURRENT_SPACE" ]]; then
          if [[ "${_HERDR_INITIALIZED_SPACE:-}" != "$_CURRENT_SPACE" ]]; then
            export _HERDR_INITIALIZED_SPACE="$_CURRENT_SPACE"
            cd "$WORK_DIR"
          fi
        elif [[ "$PWD" == "$HOME" || "$PWD" == "/" ]]; then
          cd "$WORK_DIR"
        fi
      fi
    '';
    shellAliases = {
      g = "git";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline -20";
      gpl = "git pull --rebase";
      gp = "git push";
      gpf = "git push --force-with-lease";
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gb = "git branch";
      gsw = "git switch";
      gcl = "git clone --recurse-submodules";
      gsu = "git submodule update --init --recursive";
      ct = "cleartool";
      cco = "cleartool checkout -nc";
      cci = "cleartool checkin -nc";
      cunco = "cleartool uncheckout -rm";
      clsco = "cleartool lsco -cview -me";
      cpwv = "cleartool pwv";
      cdiff = "cleartool diff -pred";
      chist = "cleartool lshistory";
      cdesc = "cleartool describe";
      v = "nvim";
      lg = "lazygit";
      rebuild = "~/dotfiles/rebuild.sh";
      ccd = "claude --dangerously-skip-permissions";
      ccdr = "claude --dangerously-skip-permissions -r";
      cca = "claude --enable-auto-mode";
      ccar = "claude --enable-auto-mode -r";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      command_timeout = 60000;
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ------------------------------------------------------------------ git
  programs.git = {
    enable = true;
    settings = {
      user.name = "Sungin Kim";
      user.email = "sunginapp@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      submodule.recurse = true;
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
      url."https://github.com/".insteadOf = "git@github.com:";
    };
  };
}
