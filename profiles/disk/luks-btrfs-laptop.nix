# LUKS + btrfs disk layout for the laptops, with a separate encrypted swap.
#
# Two LUKS containers, matching johnae/world's disko-btrfs-workstation.nix:
#   ESP   vfat  /boot
#   swap  LUKS  -> swap   (resumeDevice, so hibernation works)
#   root  LUKS  -> btrfs  (/root /nix /home /var)
#
# Why a separate swap container and not a swapfile in the btrfs: an active
# btrfs swapfile cannot be resumed from — systemd needs both `resume=` and
# `resume_offset=`, and the offset has to be recomputed whenever the file moves
# (btrfs.readthedocs.io Swapfile; disko#651).
#
# Why two containers and not LVM on one: hibernation is already covered, so LVM
# would add a layer without removing a step. systemd caches the passphrase in
# the kernel keyring within one boot (crypttab's password-cache=yes is the
# default), so the second container unlocks without a second prompt.
#
# Machine-specific numbers are NOT here. Sizes that depend on RAM live in each
# host's hardware-configuration.nix, next to the rest of its machine facts.
#
# Use (the layout is imported by the host config, there is no --disko flag):
#   nixos-anywhere --flake .#<host> --target-host root@<ip> \
#     --disk main /dev/nvme0n1 \
#     --disk-encryption-keys /tmp/luks-password /tmp/luks-password
_:

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1"; # placeholder, override with --disk main DEVICE
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

          # Size set per host: it must be >= RAM to hibernate, and the sensible
          # number depends on the machine. See hosts/*/hardware-configuration.nix.
          swap = {
            content = {
              type = "luks";
              name = "cryptswap";
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
              };
              passwordFile = "/tmp/luks-password";
              content = {
                type = "swap";
                resumeDevice = true;
              };
            };
          };

          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
              };
              passwordFile = "/tmp/luks-password";
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

                  "/var" = {
                    mountpoint = "/var";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                    ];
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
