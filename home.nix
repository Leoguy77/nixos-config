# Home Manager configuration (legacy - for backwards compatibility)
# This file imports all modular home configurations
#
# NOTE: The preferred way to build this system is now via flakes:
#   home-manager switch --flake .#leoguy77@surface
#
# This file is kept for compatibility with non-flake workflows
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/home/core.nix
    ./modules/home/development.nix
    ./modules/home/desktop.nix
    ./modules/home/pi.nix
  ];

  # Enable all modules
  modules.home.core.enable = true;
  modules.home.development.enable = true;
  modules.home.desktop.enable = true;
  modules.home.pi.enable = true;
}
