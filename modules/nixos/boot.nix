# Boot configuration
# Note: kernel modules and cpu microcode are set in hardware-configuration.nix
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.boot;
in

{
  options.modules.boot = {
    enable = lib.mkEnableOption "boot module";
    systemdBoot = lib.mkEnableOption "systemd-boot";
    efi = lib.mkEnableOption "EFI variables";
  };

  config = lib.mkIf cfg.enable {
    # Bootloader
    boot.loader.systemd-boot = {
      enable = lib.mkDefault cfg.systemdBoot;
      # Keep many entries so a failing generation leaves plenty of known-good
      # fallbacks in the menu (was 10; autoUpgrade + GC would prune good ones).
      configurationLimit = lib.mkDefault 40;
    };
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault cfg.efi;
    boot.loader.timeout = lib.mkDefault 3;

    # Firmware
    hardware.enableRedistributableFirmware = lib.mkDefault true;
  };
}
