{
  description = "Leon's NixOS System Configuration";

  inputs = {
    # NixOS unstable channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # LLM Agents
    llm-agents.url = "github:numtide/llm-agents.nix";
    
    # Auto CPU Frequency (power management)
    auto-cpufreq.url = "github:AdnanHodzic/auto-cpufreq";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
    # System architecture
    system = "x86_64-linux";
    
    # Import pkgs with overlays and config
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    
    # Shared special arguments for all configurations
    specialArgs = {
      inherit inputs;
    };
    
    # Common modules for all NixOS configurations
    commonModules = [
      home-manager.nixosModules.home-manager
      inputs.auto-cpufreq.nixosModules.default
    ];
  in {
    # NixOS configurations
    nixosConfigurations = {
      surface = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = commonModules ++ [
          ./hosts/surface
        ];
      };
    };
    
    # Home Manager standalone configurations
    homeConfigurations = {
      "leoguy77@surface" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./hosts/surface/home.nix
        ];
        extraSpecialArgs = specialArgs;
      };
    };
  };
}
