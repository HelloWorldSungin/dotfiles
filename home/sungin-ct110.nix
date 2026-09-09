{ config, lib, pkgs, ... }:

let
  devToolsPins = pkgs.writeText "dev-tools-versions.sh" (builtins.readFile ../config/dev-tools-versions.sh);
  devToolsFlakeLock = pkgs.writeText "flake.lock" (builtins.readFile ../flake.lock);
  nvimPluginLock = pkgs.writeText "nvim-lazy-lock.json" (builtins.readFile ../config/nvim/lazy-lock.json);
  devToolsUpdateChecker = pkgs.writeShellApplication {
    name = "dev-tools-check-updates";
    text = ''
      export DEV_TOOLS_PINS_FILE=${devToolsPins}
      export DEV_TOOLS_FLAKE_LOCK_FILE=${devToolsFlakeLock}
      export DEV_TOOLS_NVIM_LOCK_FILE=${nvimPluginLock}
      ${builtins.readFile ../bin/dev-tools-check-updates}
    '';
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
  # Guarded, opt-in companion to the checker. Installed on PATH but deliberately
  # NOT given a timer: it only ever runs when the captain invokes it. The checker
  # is on its runtime PATH so the tool's own detection delegation resolves.
  devToolsApplyUpdates = pkgs.writeShellApplication {
    name = "dev-tools-apply-updates";
    text = ''
      export DEV_TOOLS_PINS_FILE=${devToolsPins}
      ${builtins.readFile ../bin/dev-tools-apply-updates}
    '';
    bashOptions = [ ]; # Applies each tier independently and handles failures itself.
    runtimeInputs = with pkgs; [
      coreutils
      git
      jq
      nodejs_22
      devToolsUpdateChecker
    ];
  };
  devToolsUpdateCheckRun = pkgs.writeShellScript "dev-tools-update-checker-run" ''
    export CHROME_DEVTOOLS_AXI_CHROME_ARGS=${lib.escapeShellArg config.home.sessionVariables.CHROME_DEVTOOLS_AXI_CHROME_ARGS}
    ${devToolsUpdateChecker}/bin/dev-tools-check-updates --force --json
    ${devToolsUpdateChecker}/bin/dev-tools-check-updates --health --json
  '';
in
{
  imports = [ ./common.nix ];

  home.username = "sungin";
  home.homeDirectory = "/home/sungin";

  home.packages = with pkgs; [
    tea # Gitea CLI - BZ-SIM (and other CT101-hosted repos) track issues there
    chromium # headless browser for chrome-devtools-axi E2E testing
    ghdl     # open-source VHDL simulator
    gtkwave  # view GHDL-produced .ghw/.vcd waveforms
    devToolsApplyUpdates # opt-in guarded auto-apply for the safe update tiers
  ];

  home.sessionVariables = {
    CHROME_DEVTOOLS_AXI_CHROME_ARGS = "--no-sandbox --disable-dev-shm-usage --disable-gpu";
  };

  programs.zsh = {
    envExtra = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
    '';
    initContent = ''
      if [[ -o login ]]; then
        ${devToolsUpdateChecker}/bin/dev-tools-check-updates --startup
      fi
    '';
  };

  # ------------------------------------------------ developer-tool updates
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
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      ForwardAgent = false;
      AddKeysToAgent = "no";
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
      ControlMaster = "no";
      ControlPath = "~/.ssh/master-%r@%n:%p";
      ControlPersist = "no";
    };
    settings."gitea.arknode" = {
      HostName = "192.168.68.101";
      Port = 2222;
      User = "git";
      IdentityFile = "~/.ssh/id_ed25519";
    };
    settings."loq" = {
      HostName = "192.168.68.83";
      User = "root";
      IdentityFile = "~/.ssh/id_ed25519";
    };
  };
}
