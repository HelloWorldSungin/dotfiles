{
  description = "Sungin's dotfiles - ArkNode agent host (CT110) & MacBook Air client";

  inputs = {
    # Pinned to a stable release so rebuilds are predictable.
    # Update deliberately with `nix flake update`, never by surprise.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    homeConfigurations = {
      # Server-side environment: everything agents and I use over SSH on CT110.
      "sungin@ct110" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [ ./home/sungin-ct110.nix ];
      };

      # Mac client environment (aarch64-darwin for Apple Silicon MacBook Air)
      "sunginkim@macbook" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [ ./home/sungin-mac.nix ];
      };
    };
  };
}
