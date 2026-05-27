# Boot configuration
# Note: kernel modules and cpu microcode are set in hardware-configuration.nix
{ config, pkgs, lib, ... }:

{
  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Firmware
  hardware.enableRedistributableFirmware = true;
}
