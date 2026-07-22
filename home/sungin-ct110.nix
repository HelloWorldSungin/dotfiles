{ config, lib, pkgs, ... }:

let
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
  imports = [ ./common.nix ];

  home.username = "sungin";
  home.homeDirectory = "/home/sungin";

  home.packages = with pkgs; [
    tea # Gitea CLI - BZ-SIM (and other CT101-hosted repos) track issues there
    chromium # headless browser for chrome-devtools-axi E2E testing
    ghdl     # open-source VHDL simulator
    gtkwave  # view GHDL-produced .ghw/.vcd waveforms
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
    matchBlocks."gitea.arknode" = {
      hostname = "192.168.68.101";
      port = 2222;
      user = "git";
      identityFile = "~/.ssh/id_ed25519";
    };
    matchBlocks."loq" = {
      hostname = "192.168.68.83";
      user = "root";
      identityFile = "~/.ssh/id_ed25519";
    };
  };
}
