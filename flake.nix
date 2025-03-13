outputs = { self, nixpkgs, nixos-hardware, home-manager }@attrs:
  let
    commonModules = name: [
      {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        networking.hostName = name;
      }
      ./hosts/${name}
    ];
    mkSystem = name: cfg: nixpkgs.lib.nixosSystem {
      system = cfg.system or "x86_64-linux";
      modules = (commonModules name) ++ (cfg.modules or []);
      specialArgs = attrs;
    };
    systems = {

      desktop = {
        modules = [
          home-manager.nixosModules.home-manager
        ];
      };

    };
  in {
    nixosConfigurations = nixpkgs.lib.mapAttrs mkSystem systems;
  };
