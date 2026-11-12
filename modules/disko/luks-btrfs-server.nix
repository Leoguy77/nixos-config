# LUKS-encrypted BTRFS layout for small servers deployed with nixos-anywhere.
#
# Differences to luks-btrfs.nix (the desktop layout):
#   - separate /var subvolume (mail/data stores live there, and it keeps
#     RocksDB off the snapshotted root)
#   - 2 GB swapfile instead of 8 GB (20-40 GB VPS disks)
#
# Use (the layout is imported by the host config, there is no --disko flag):
#   nixos-anywhere --flake .#<host> --target-host root@<ip> \
#     --disk main /dev/vda \
#     --disk-encryption-keys /tmp/luks-password /tmp/luks-password
#
# The passphrase written to the LUKS header at install time is the one you type
# at boot (or send over the initrd SSH connection).
_:

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/vda"; # placeholder, override with --disk main DEVICE
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
            };
          };

          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings = {
                allowDiscards = true;
                # No key file: the passphrase is entered in the initrd, either
                # on the provider console or over initrd SSH.
                bypassWorkqueues = true;
              };
              passwordFile = "/tmp/luks-password"; # injected by --disk-encryption-keys
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                    ];
                  };

                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                      "nodiratime"
                    ];
                  };

                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                    ];
                  };

                  # A plain mail spool is written sequentially, so CoW costs
                  # little here; nodatacow is kept from the previous
                  # database-backed stack, where in-place page rewrites
                  # fragmented badly.
                  "/var" = {
                    mountpoint = "/var";
                    mountOptions = [
                      "nodatacow"
                      "noatime"
                    ];
                  };

                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = "2G";
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
