{ config, lib, pkgs, ... }:

let
  # All config symlinks point back into this repo clone, so editing
  # ~/.config/nvim (or letting a tool edit its own config) edits the repo.
  # That keeps every runtime change version-controlled - Kun's core trick.
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
  devToolsUpdateCheckRun = pkgs.writeShellScript "dev-tools-update-checker-run" ''
    export CHROME_DEVTOOLS_AXI_CHROME_ARGS=${lib.escapeShellArg config.home.sessionVariables.CHROME_DEVTOOLS_AXI_CHROME_ARGS}
    ${devToolsUpdateChecker}/bin/dev-tools-check-updates --force --json
    ${devToolsUpdateChecker}/bin/dev-tools-check-updates --health --json
  '';
in
{
  home.username = "sungin";
  home.homeDirectory = "/home/sungin";
  home.stateVersion = "25.11"; # set once, never touch again

  programs.home-manager.enable = true; # gives us the `home-manager` CLI

  home.packages = with pkgs; [
    devToolsUpdateChecker
    gh
    tea # Gitea CLI - BZ-SIM (and other CT101-hosted repos) track issues there
    lazygit
    nodejs_22 # required by the axi tools (Node 20+) and npm-installed harnesses
    uv       # Python runner for ark-hermes-agent's stock-runner scripts
    bats     # runs ark-hermes-agent's .bats shell tests
    ripgrep
    fd
    fzf
    jq
    tree
    htop
    unzip
    chromium # headless browser for chrome-devtools-axi E2E testing
    ghdl     # open-source VHDL simulator - lets agents compile/simulate FPGA (fast-frequency-card) changes
    gtkwave  # view GHDL-produced .ghw/.vcd waveforms (headless-generate, inspect on demand)
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    # npm's default global prefix would be the read-only /nix/store, so
    # global installs (codex, the axi tools) go to a user-writable prefix.
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    # chrome-devtools-axi drives a headless Chrome; inside this LXC the
    # sandbox can't initialize, so pass the flags that let it launch.
    # Verified: about:blank snapshot + screenshot succeed with these.
    CHROME_DEVTOOLS_AXI_CHROME_ARGS = "--no-sandbox --disable-dev-shm-usage --disable-gpu";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin" # official CLI installers use this prefix
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

  # --------------------------------------------------- vendored skills
  # The `vault` skill (OKF knowledge ops) vendored from HelloWorldSungin/
  # ark-skills. Deliberately vendored as a standalone skill, NOT via the
  # ark-skills plugin, to avoid pulling in the ark workflow router / /ark-*
  # commands - firstmate stays the only orchestrator. Symlinked into every
  # harness that supports agent-skills so it is not claude-only.
  home.file.".claude/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";
  home.file.".pi/agent/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";
  home.file.".agents/skills/vault/SKILL.md".source = link "skills/vault/SKILL.md";

  # ------------------------------------------------ vendored pi extensions
  # fusion-harness — dual-model harness (architect + builder). Vendored so a
  # fresh `home-manager switch` reproduces the extension instead of relying on
  # an imperative `pi install -l`.
  home.file.".pi/agent/extensions/fusion-harness".source = link "pi/extensions/fusion-harness";

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

      # The weekly timer refreshes the update cache. Login shells read that
      # cache and check only local health, so opening one never waits on network.
      if [[ -o login ]]; then
        ${devToolsUpdateChecker}/bin/dev-tools-check-updates --startup
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
      # high-agency claude (Kun's pattern); ccdr resumes the last session
      ccd = "claude --dangerously-skip-permissions";
      ccdr = "claude --dangerously-skip-permissions -r";
      # fusion-harness: dual-model harness with explicit models and thinking levels.
      pi-fusion = "pi -e $HOME/.pi/agent/extensions/fusion-harness/fusion-harness.ts --architect openai-codex/gpt-5.6-sol --architect-thinking xhigh --builder zai/glm-5.2 --builder-thinking max";
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

  # ------------------------------------------------ developer-tool updates
  # Check update availability and local wiring health. Never apply an update.
  systemd.user.services.dev-tools-update-checker = {
    Unit.Description = "Check personal developer-tool updates and health";
    Service = {
      Type = "oneshot";
      ExecStart = devToolsUpdateCheckRun;
    };
  };

  systemd.user.timers.dev-tools-update-checker = {
    Unit.Description = "Weekly personal developer-tool update check";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
      Unit = "dev-tools-update-checker.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # ------------------------------------------------------------------ ssh
  # Gitea on CT101 hosts some project repos (BZ-SIM, fast-frequency-card).
  # The sungin@ct110 pubkey must be registered in Gitea's UI once.
  programs.ssh = {
    enable = true;
    matchBlocks."gitea.arknode" = {
      hostname = "192.168.68.101";
      port = 2222;
      user = "git";
      identityFile = "~/.ssh/id_ed25519";
    };
    # LOQ dev/agent host (ark-dev-server). The sungin@ct110 pubkey is
    # registered in root's authorized_keys on LOQ. Reach it with `ssh loq`.
    matchBlocks."loq" = {
      hostname = "192.168.68.83";
      user = "root";
      identityFile = "~/.ssh/id_ed25519";
    };
  };

  # ------------------------------------------------------------------ git
  programs.git = {
    enable = true;
    settings = {
      user.name = "Sungin Kim";
      user.email = "sunginapp@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      # gh can't write this itself (this git config is a read-only nix
      # symlink), so the gh-as-credential-helper wiring lives here.
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
      # The sungin ed25519 key is not registered with GitHub, so git@ SSH
      # remotes (e.g. ark-hermes-agent's submodules) fail. Rewrite them to
      # HTTPS so they use the gh credential helper above.
      url."https://github.com/".insteadOf = "git@github.com:";
    };
  };
}
