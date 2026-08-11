{
  description = "NixOS system config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix = {
      url = "github:helix-editor/helix/master";
      # Dedupe the closure: reuse our nixpkgs instead of Helix pulling its own.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      sops-nix,
      zen-browser,
      ...
    }:
    let
      # Every host shares these modules; `hostModule` adds the per-machine bits
      # (hostname, GPU, LUKS, stateVersion) from hosts/<name>/default.nix.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            ./modules/audio.nix # PipeWire + ULN-8; shared (the interface roams between hosts)
            ./modules/thunderbolt.nix # Thunderbolt display support
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                pkgsUnstable = import nixpkgs-unstable {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                };
              };
              home-manager.users.jakek = import ./home/home.nix;
            }
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        jakek = mkHost ./hosts/desktop;

        # Laptop — uncomment once hosts/laptop/hardware-configuration.nix exists
        # and the laptop's host key is in .sops.yaml. See hosts/laptop/default.nix
        # for the full bootstrap checklist.
        # jakek-laptop = mkHost ./hosts/laptop;
      };

      # `nix fmt`, and used by `nix flake check` to verify formatting.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
    };
}
