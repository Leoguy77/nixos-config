# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ pkgs, inputs, ... }:

{
  imports =
    [
      inputs.hardware.nixosModules.common-cpu-amd
      inputs.hardware.nixosModules.common-gpu-amd
      inputs.hardware.nixosModules.common-pc-ssd
      ./hardware-configuration.nix
      ../common/global
      ../common/users/leoguy77
      #./common/optional/greetd.nix
      ../common/optional/pipewire.nix
      #../common/optional/quietboot.nix
      ../common/optional/wireless.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking = {
    hostName = "surface";
    useDHCP = true;
  };
  environment.systemPackages = with pkgs; [
    hello
  ];

  hardware.graphics.enable = true;

  system.stateVersion = "24.11";

}

