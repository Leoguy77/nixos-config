# Security settings
{ config, pkgs, lib, ... }:

{
  # Security
  security.rtkit.enable = true;
  security.sudo.wheelNeedsPassword = true;

  # Audio requires rtkit
  hardware.pulseaudio.enable = false;
}
