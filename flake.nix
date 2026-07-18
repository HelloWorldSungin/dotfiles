{
  description = "Sungin's dotfiles - ArkNode agent host (CT110) first, Mac client later";

  inputs = {
    # Pinned to a stable release so rebuilds are predictable (Kun pins too).
    # Update deliberately with `nix flake update`, never by surprise.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    # Server-side environment: everything agents and I use over SSH on CT110.
    homeConfigurations."sungin@ct110" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [ ./home/sungin-ct110.nix ];
    };

    # Later: a Mac client target (aarch64-darwin, nix-darwin + home-manager)
    # sharing modules with the server config. Deliberately not started yet -
    # the server workflow gets proven first.
  };
}
