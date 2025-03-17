{
  description = "My NixOS configuration";


  inputs = {
    # Nix ecosystem
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    systems.url = "github:nix-systems/default-linux";

    hardware.url = "github:nixos/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    nix-colors.url = "github:misterio77/nix-colors";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-24_11.follows = "nixpkgs-stable";
    };
    nix-gl = {
      url = "github:nix-community/nixgl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-minecraft = {
      url = "github:misterio77/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    themes = {
      url = "github:misterio77/themes";
      inputs.systems.follows = "systems";
    };
    # Third party programs, packaged with nix
    nix-gaming = {
      # url = "github:fufexan/nix-gaming";
      url = "github:misterio77/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    systems,
    ...
  } @ inputs: let
    inherit (self) outputs;
    lib = nixpkgs.lib // home-manager.lib;
    forEachSystem = f: lib.genAttrs (import systems) (system: f pkgsFor.${system});
    pkgsFor = lib.genAttrs (import systems) (
      system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
    );
  in {
    inherit lib;
    homeManagerModules = import ./modules/home-manager;
    #overlays = import ./overlays {inherit inputs outputs;};
    #packages = forEachSystem (pkgs: import ./pkgs {inherit pkgs;});
    nixosConfigurations = {
      # Main desktop
      surface = lib.nixosSystem {
        modules = [./hosts/surface];
        specialArgs = {
          inherit inputs outputs;
        };
      };
    };

    homeConfigurations = {
      # Standalone HM only

      # Main desktop
      "leoguy77@surface" = lib.homeManagerConfiguration {
        modules = [./home/leoguy77/surface.nix ./home/leoguy77/nixpkgs.nix];
        pkgs = pkgsFor.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
      };
    };
  };
}
