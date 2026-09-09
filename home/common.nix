{ config, lib, pkgs, devTools, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  imports = [ ./dev-tools.nix ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.packages = (with devTools; [
    checker
    pinnedInstaller
    claudeSpendPinned
  ]) ++ (with pkgs; [
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
  ]);

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
    # Preserve the pre-26.05 provider defaults explicitly across channel updates.
    withPython3 = true;
    withRuby = true;
    # Home Manager 26.05 generates provider Lua. Keep it in the wrapper so it
    # does not collide with the live out-of-store nvim configuration tree.
    sideloadInitLua = true;
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

  # ------------------------------------------------- pi model overrides
  # Opts GPT-5.6 Sol, GPT-5.6 Terra and GPT-6 Astra into OpenAI's 1,050,000-token
  # long-context window. `modelOverrides` patches the three built-in models in
  # place, so the rest of the openai-codex catalog (Luna included) keeps its
  # 272,000 default and every built-in model's pricing metadata is preserved.
  # See docs/agents.md.
  home.file.".pi/agent/models.json".source = link "pi/models.json";

  # --------------------------------------------------- codex context window
  # ~/.codex/config.toml is machine-maintained (project trust entries, hook
  # approvals, TUI preferences), so home-manager owns exactly one key in it via
  # an atomic idempotent merge rather than taking over the file.
  home.activation.codexContextWindow =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${devTools.codexSetContextWindow}/bin/codex-set-context-window
    '';

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
    '';
    shellAliases = {
      g = "git";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline -20";
      gpl = "git pull --rebase";
      v = "nvim";
      lg = "lazygit";
      rebuild = "~/dotfiles/rebuild.sh";
      ccd = "claude --dangerously-skip-permissions";
      ccdr = "claude --dangerously-skip-permissions -r";
      cca = "claude --enable-auto-mode";
      ccar = "claude --enable-auto-mode -r";
      ccm = "claude-monitor --plan max20 --theme dark";
      cspend = "claude-spend-pinned";
      pi-fusion = "pi -e $HOME/.pi/agent/extensions/fusion-harness/fusion-harness.ts --architect openai-codex/gpt-5.6-sol --architect-thinking xhigh --builder zai/glm-5.2 --builder-thinking max";

      # ArkNode AI & LOQ server management
      arknode-ai-sleep = "ssh root@192.168.68.10 \"systemctl suspend\"";
      arknode-ai-wake = "wakeonlan 10:ff:e0:a1:52:48 && echo \"⏳ Waiting 10 seconds for ArkNode AI to wake...\" && sleep 10 && echo \"✅ ArkNode AI should be awake! Connecting...\" && ssh root@192.168.68.10";
      arknode-ai-status = "ping -c 2 192.168.68.10 && ssh root@192.168.68.10 \"uptime && echo && pct list\"";
      agent-tunnel = "ssh -L 9119:127.0.0.1:9119 -N root@192.168.68.83";
      codebase-gui = "codebase-memory-mcp --ui=true --port=9749";
      ct110-lav-gateway = "ssh -N ct110-lav";
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
    settings = {
      user.name = "Sungin Kim";
      user.email = "sunginapp@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
      url."https://github.com/".insteadOf = "git@github.com:";
    };
  };
}
