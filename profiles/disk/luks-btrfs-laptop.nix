# LUKS + btrfs disk layout for the laptops, with a separate encrypted swap.
#
# Two LUKS containers, matching johnae/world's disko-btrfs-workstation.nix:
#   ESP   vfat  /boot
#   swap  LUKS  -> swap   (resumeDevice, so hibernation works)
#   root  LUKS  -> btrfs  (/root /nix /home /var)
#
# With modules.disk.ephemeralRoot the root subvolume is replaced by a tmpfs and
# /var joins it, so a reboot leaves only what profiles/state.nix persists.
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
{
  config,
  lib,
  ...
}:

let
  # Ephemeral root: `/` is a tmpfs and only the declared subvolumes survive a
  # reboot. This is the option that makes impermanence mean something — without
  # it profiles/state.nix is a no-op, because everything it binds from /persist
  # is already on a persistent root anyway.
  #
  # /home stays a real subvolume even here. User data is not configuration, and
  # "your files are gone unless listed" is a data-loss feature, not a security
  # one. /var goes ephemeral because it is exactly the set of things
  # profiles/state.nix already enumerates.
  #
  # tmpfs size is a ceiling, not an allocation — it grows on demand. 8G is sized
  # for build temp dirs in /tmp; the root itself holds only /etc, /root and /tmp.
  # Keep it well under RAM: every page a tmpfs holds is a page the hibernation
  # image also has to write to swap.
  ephemeralRoot = config.modules.disk.ephemeralRoot;
in

{
  options.modules.disk.ephemeralRoot = lib.mkEnableOption "an ephemeral (tmpfs) root, with declared paths persisted";

  config.disko.devices = {
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
                # Under an ephemeral root, / and /var are the two things that must
                # NOT be subvolumes: / comes from the tmpfs and /var is rebuilt
                # from what profiles/state.nix persists into it. /home stays a
                # real subvolume on purpose — user data is not configuration, and
                # "your files are gone unless listed" is data loss dressed up as
                # a feature. Filtering here keeps one subvolume list, not two.
                #
                # /home must additionally be neededForBoot (set in
                # profiles/state.nix): impermanence links persisted user paths
                # into it before local-fs.target.
                subvolumes = lib.filterAttrs (name: _: !(ephemeralRoot && (name == "/root" || name == "/var"))) {
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

                  # Where profiles/state.nix keeps the paths that must survive a
                  # wiped root. Needed early: impermanence bind-mounts out of here
                  # before local-fs.target, and the sops/age host key is one of
                  # those files. Harmony with the rest of the mount options.
                  "/persist" = {
                    mountpoint = "/persist";
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

    # The ephemeral root itself: a tmpfs, so disko writes nothing to a device for
    # it. `nodev` is disko's type for exactly this.
    nodev."/" = lib.mkIf ephemeralRoot {
      fsType = "tmpfs";
      mountOptions = [
        "size=8G"
        "mode=755"
      ];
    };
  };
}
