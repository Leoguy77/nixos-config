# Home Manager configuration
# This file imports all modular home configurations
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/home/core.nix
    ./modules/home/development.nix
    ./modules/home/desktop.nix
    ./modules/home/pi.nix
  ];
}
