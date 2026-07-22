{ config, ... }:

# LUKS-encrypted BTRFS disk layout for nixos-anywhere.
# Use: nixos-anywhere --disko modules/disko/luks-btrfs.nix --disk main DEVICE ...
#
# Device is overridden by --disk main DEVICE.
# LUKS password injected via --disk-encryption-keys /tmp/secret /tmp/luks-password.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";                     # placeholder, override with --disk main DEVICE
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypted";
              settings.allowDiscards = true;
              passwordFile = "/tmp/luks-password";  # injected by --disk-encryption-keys
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" "nodiratime" ];
                  };
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = "8G";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
