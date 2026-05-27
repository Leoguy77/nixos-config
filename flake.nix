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

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = {
        inherit inputs;
      };

      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        inputs.auto-cpufreq.nixosModules.default
      ];
    };
  };
}
