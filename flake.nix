{
  description = "NixOS system config";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix.url = "github:helix-editor/helix/master";
    zen-browser = {
     url = "github:0xc000022070/zen-browser-flake";
     inputs.nixpkgs.follows = "nixpkgs";
     inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, sops-nix, zen-browser, ...}: {
   nixosConfigurations.jakek = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
       ./configuration.nix
       sops-nix.nixosModules.sops
       home-manager.nixosModules.home-manager
       { 
         home-manager.useGlobalPkgs = true;
         home-manager.useUserPackages = true;
         home-manager.extraSpecialArgs = { inherit inputs; };
         home-manager.users.jakek = import ./home.nix;
       }
      ];
    };
  };
}
