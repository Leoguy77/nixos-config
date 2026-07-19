# System-wide packages
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.packages;
in

{
  options.modules.packages = {
    enable = lib.mkEnableOption "packages module";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra system-wide packages";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Core utilities
      vim
      wget
      curl
      git
      
      # System monitoring
      htop
      btop
      fastfetch  # Replacement for unmaintained neofetch
      
      # File management
      unzip
      p7zip
      
      # Network tools
      networkmanagerapplet
      
      # Power management
      # caffeine-ng is managed via Home Manager services.caffeine in per-host home.nix
      
      # User-provided extra packages
    ] ++ cfg.extraPackages;
  };
}
