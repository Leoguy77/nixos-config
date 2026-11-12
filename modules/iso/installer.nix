# Minimal bootable NixOS installer ISO for hosts that nixos-anywhere cannot
# bootstrap.
#
# Why this exists: nixos-anywhere's kexec image puts 449 MiB of initrd in RAM
# (ramfs, unswappable) and then nix-copies a 446 MiB disko closure on top. A
# 1 GB VPS has 963 MiB, so that is an OOM. Its `--no-disko-deps` escape hatch
# uploads only the script, but the kexec image ships almost none of the
# partitioning tools, so it trades an OOM for `command not found`.
#
# This ISO is the same idea as the stock one -- root is a squashfs on the
# medium, so the live system costs only ~54 MiB of RAM -- plus three things the
# stock image lacks:
#
#   1. static networking, so the box is reachable without touching VNC,
#   2. the admin SSH key, so root login works with no password,
#   3. every partitioning tool disko needs on sshd's PATH, which makes
#      --no-disko-deps safe (19 KiB copied into RAM instead of 446 MiB).
#
# nixos-anywhere then detects VARIANT_ID=installer and skips kexec by itself.
{
  config,
  lib,
  pkgs,
  myvars,
  ...
}:

let
  cfg = config.modules.isoInstaller;

  hostCfg = myvars.networking.hostsAddr.${cfg.hostname};
in
{
  options.modules.isoInstaller = {
    enable = lib.mkEnableOption "a pre-configured NixOS installer ISO";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = ''
        Host under `myvars.networking.hostsAddr` whose static address, gateway
        and admin keys are baked in. The ISO is then reachable over SSH with no
        console step.
      '';
    };

    adminKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Same ed25519 key the hosts use. Public data, already in git.
      default = [ myvars.git.signingKey ];
      description = "SSH keys allowed to log in as root on the live system.";
    };
  };

  config = lib.mkIf cfg.enable {
    # mkForce because installation-cd-minimal sets VARIANT_ID=installer with a
    # normal priority; we only need it to stay "installer" so nixos-anywhere's
    # get-facts.sh recognises the target and skips kexec.
    system.nixos.variant_id = lib.mkForce "installer";

    isoImage = {
      # This is a VPS, so EFI only -- no legacy BIOS boot needed.
      makeEfiBootable = true;
      makeUsbBootable = true;
    };

    # Distinctive on purpose: this image has the host's key baked in, so it must
    # never be mistaken for the stock installer. mkForce because iso-image.nix
    # sets baseName unconditionally. image.fileName derives from it.
    image.baseName = lib.mkForce "nixos-installer-${cfg.hostname}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";

    # ── Static networking ────────────────────────────────────────────────────
    # Defined in the initrd AND at stage 2. Both are needed: the initrd copy
    # puts the address up before sshd starts (no console work), and the stage-2
    # copy keeps it after switch-root.
    #
    # NetworkManager MUST stay off. installation-device.nix enables it, and it
    # would claim eth0 in stage 2, drop our static address and DHCP it -- which
    # severs the SSH session nixos-anywhere is still copying the closure over.
    networking = {
      networkmanager.enable = lib.mkForce false;
      useNetworkd = true;
      useDHCP = false;
    };

    systemd.network.networks."10-eth0" = {
      # Match on link type, not name: the NIC answers to eth0, enp0s3 or ens3
      # depending on what udev decides. A wrong name here means no address, no
      # sshd, and no way in without the console this ISO exists to avoid.
      matchConfig.Type = "ether";
      address = [
        "${hostCfg.ipv4}/22"
        "${hostCfg.ipv6}/64"
      ];
      routes = [
        # netcup's gateway is outside the /22 interface route, so it must be
        # marked on-link or the kernel rejects it ("Nexthop has invalid
        # gateway"). This is what `ip route add ... onlink` does by hand.
        {
          Destination = "0.0.0.0/0";
          Gateway = hostCfg.ipv4Gateway;
          GatewayOnLink = true;
        }
        {
          Destination = "::/0";
          Gateway = hostCfg.ipv6Gateway;
        }
      ];
    };

    # Done in the initrd, so the address is up before sshd starts.
    boot.initrd.systemd.network = {
      enable = true;
      inherit (config.systemd.network) networks;
      wait-online.enable = false;
    };

    # ── Root login by key only ───────────────────────────────────────────────
    # The key is public data that already lives in git, so baking it in leaks
    # nothing that a `git clone` of this flake does not.
    users.users.root.openssh.authorizedKeys.keys = cfg.adminKeys;

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    # ── Everything disko needs, so --no-disko-deps works ─────────────────────
    # systemPackages alone is not enough: a `nixos-anywhere` disko script is run
    # over a non-login SSH session, and sshd's unit PATH wins over the profile.
    # Without this, --no-disko-deps fails with `command not found` (the stock
    # kexec image has exactly that bug). With it, the disko closure copied into
    # RAM is 19 KiB instead of 446 MiB.
    environment.systemPackages = with pkgs; [
      gptfdisk
      parted
      dosfstools
      btrfs-progs
      cryptsetup
      util-linux
      mdadm
      disko
      rsync
      jq
    ];

    systemd.services.sshd.path = with pkgs; [
      bash
      coreutils
      gnused
      gptfdisk
      parted
      dosfstools
      btrfs-progs
      cryptsetup
      util-linux
      mdadm
    ];

    # Swap on the live medium: the install writes a 1.8 GiB closure into the
    # target, and 909 MiB of usable RAM plus 2 GiB of zram is comfortable.
    zramSwap = {
      enable = true;
      memoryPercent = 100;
      priority = 100;
    };
  };
}
