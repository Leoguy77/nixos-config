# Hardware configuration for the netcup VPS (KVM guest).
#
# Hand written on purpose:
#   - this is a virtual machine, so the only thing that matters is the virtio
#     stack, and that is knowable up front
#   - nixos-anywhere's --generate-hardware-config would add `fileSystems`, which
#     would then fight the disko layout that actually creates them
#
# If the VPS turns out not to use virtio (check `lspci` on the provider image),
# regenerate this with `nixos-generate-config` and drop the fileSystems block.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "ata_piix"
    "dm_mod"
    "dm_crypt"
    "sd_mod"
    "sr_mod"
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
  ];

  boot.kernelModules = [ "virtio_net" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
