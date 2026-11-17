# Hardware configuration for kirito — Dell Latitude 5410.
#
# Edited by hand from the `nixos-generate-config` output: the generated
# `fileSystems` and `swapDevices` blocks are GONE on purpose. The disk layout
# lives in `profiles/disk/luks-btrfs-laptop.nix` (imported via profiles/laptop.nix)
# and disko generates the mount points from it, so keeping the ext4 UUIDs here
# would define `/` twice and every evaluation would stop on the conflict.
#
# That is also why `scripts/deploy.sh` refuses a hardware-configuration.nix
# containing `fileSystems`: one of the two has to be the source of truth.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Swap must be at least RAM to hibernate, and sleeping is the whole point of a
  # laptop. RAM is 16 GB; +2 GB covers the image overhead and the compressed
  # pages that do not fit exactly. This lives here and not in the shared layout
  # because it is a fact about THIS machine's memory, not about laptops in
  # general — the layout deliberately has no default.
  disko.devices.disk.main.content.partitions.swap.size = "18G";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
