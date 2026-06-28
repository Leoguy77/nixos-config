# Surface-specific Home Manager configuration
# This imports the modular home configuration with host-specific overrides
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../../modules/home/core.nix
    ../../modules/home/development.nix
    ../../modules/home/desktop.nix
    ../../modules/home/pi.nix
  ];

  # Enable all modules
  modules.home.core.enable = true;
  modules.home.development.enable = true;
  modules.home.desktop.enable = true;
  modules.home.pi.enable = true;

  # Surface-specific overrides
  # Example: Machine-specific desktop settings
  # dconf.settings = {
  #   "org/gnome/desktop/interface" = {
  #     color-scheme = "prefer-dark";
  #   };
  # };
}
