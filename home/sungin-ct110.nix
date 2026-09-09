{ config, lib, pkgs, devTools, ... }:

let
  devToolsUpdateCheckRun = pkgs.writeShellScript "dev-tools-update-checker-run" ''
    export CHROME_DEVTOOLS_AXI_CHROME_ARGS=${lib.escapeShellArg config.home.sessionVariables.CHROME_DEVTOOLS_AXI_CHROME_ARGS}
    ${devTools.checker}/bin/dev-tools-check-updates --force --json
    ${devTools.checker}/bin/dev-tools-check-updates --health --json
  '';
in
{
  imports = [ ./common.nix ];

  home.username = "sungin";
  home.homeDirectory = "/home/sungin";

  home.packages = (with pkgs; [
    tea # Gitea CLI - BZ-SIM (and other CT101-hosted repos) track issues there
    chromium # headless browser for chrome-devtools-axi E2E testing
    ghdl     # open-source VHDL simulator
    gtkwave  # view GHDL-produced .ghw/.vcd waveforms
  ]) ++ [
    devTools.applyUpdates # opt-in guarded auto-apply for the safe update tiers
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
        ${devTools.checker}/bin/dev-tools-check-updates --startup
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
