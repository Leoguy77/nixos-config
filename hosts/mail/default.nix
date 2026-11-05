# netcup VPS (pico G11s) — mail.lsinfra.de
#
# Stalwart (SMTP/IMAP/JMAP) + Bulwark webmail, LUKS-encrypted root unlocked over
# SSH in the initrd. See ./README.md for the deployment runbook.
{
  config,
  pkgs,
  lib,
  inputs,
  mylib,
  myvars,
  ...
}:

let
  # Confirmed on the provider image (`ip a`, `lsblk`):
  #   eth0  inet 91.132.147.216/22  (netcup: broadcast 91.132.147.255)
  #         inet6 2a03:4000:37:c32:6860:64ff:fe3b:ddb0/64
  #         link/ether 6a:60:64:3b:dd:b0   (altnames enp0s3/ens3)
  #   disk  /dev/vda (virtio)
  ipv4 = "91.132.147.216";
  ipv4Prefix = 22;
  # Provider default route is `default via 91.132.144.1 dev eth0 onlink`.
  ipv4Gateway = "91.132.144.1";

  # Not ::1 — this is the EUI-64 address derived from the NIC MAC, and it is
  # what netcup assigned. It stays stable because the MAC does.
  ipv6 = "2a03:4000:37:c32:6860:64ff:fe3b:ddb0";
  ipv6Prefix = 64;
  # Link-local gateway, also `onlink` on the provider image.
  ipv6Gateway = "fe80::1";

  # One definition, reused for stage 2 and for the initrd (the initrd needs it
  # to bring the network up before the encrypted root is unlocked).
  # Matching on link type instead of a name: the NIC answers to eth0, enp0s3
  # and ens3 depending on what udev decides.
  wan = {
    matchConfig.Type = "ether";
    address = [
      "${ipv4}/${toString ipv4Prefix}"
      "${ipv6}/${toString ipv6Prefix}"
    ];
    routes = [
      {
        Destination = "0.0.0.0/0";
        Gateway = ipv4Gateway;
        # Matches the provider's own `onlink` route.
        GatewayOnLink = true;
      }
      {
        Destination = "::/0";
        Gateway = ipv6Gateway;
        GatewayOnLink = true;
      }
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv6LinkLocalAddressGenerationMode = "eui64";
    };
  };
in

{
  imports = mylib.scanPaths ../../modules/nixos ++ [
    # The disk layout is part of the system closure: nixos-anywhere partitions
    # with it, and `disko.devices.disk.main.device` below is what
    # `--disk main /dev/vda` overrides at install time.
    inputs.disko.nixosModules.disko
    ../../modules/disko/luks-btrfs-server.nix
    ./hardware-configuration.nix
  ];

  # ── Server baseline (no desktop) ─────────────────────────────────────────
  modules.server.enable = true;
  modules.server.adminKeys = [
    # Same key as the other hosts (1Password "Github" key).
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMeOpEP8l Github"
  ];
  modules.server.initrdSshHostKey = ./initrd-ssh/ssh_host_ed25519_key;

  # Initrd SSH must never be reachable from the internet. That is handled by
  # modules.server, which enables modules.initrdTailscale on every server host:
  # tailscaled joins from the initrd (identity persisted on the ESP) and sshd
  # binds the tailnet address only. No per-host wiring, no auth key once joined.

  # ── Mail stack ───────────────────────────────────────────────────────────
  modules.mail.enable = true;
  modules.mail.hostname = "mail.lsinfra.de";
  modules.mail.webmailHostname = "webmail.lsinfra.de";
  modules.mail.acmeEmail = myvars.email;

  # No sops secrets on this host yet: decryption needs the host's age key to be
  # in .sops.yaml, which can only happen after the first boot. Flip this to true
  # once `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub` has been added.
  modules.sops.enable = false;

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "mail";
  networking.domain = "lsinfra.de";
  networking.nameservers = [
    "9.9.9.9"
    "149.112.112.112"
    "2620:fe::fe"
  ];

  systemd.network.networks."10-wan" = wan;
  boot.initrd.systemd.network.networks."10-wan" = wan;

  # ── Hardware ─────────────────────────────────────────────────────────────
  # KVM guest: nothing to import, no microcode/firmware blobs of our own.
  hardware.enableRedistributableFirmware = lib.mkDefault false;

  # ── Operations ───────────────────────────────────────────────────────────
  # Daily rebuild from GitHub. Safe again now: no secret is needed to build this
  # host (the initrd tailscale node state lives on the machine's own ESP).
  # allowReboot = false: a reboot means unlocking the disk over the tailnet.
  system.autoUpgrade = {
    enable = true;
    flake = "github:Leoguy77/nixos-config#mail";
    dates = "daily";
    persistent = true;
    allowReboot = false;
  };

  # Backups: deliberately off until an *off-site* target exists. The default
  # repository is a local path, which on a 30 GB disk would just double the
  # mail store on the same (encrypted) device. Once you have a target:
  #
  #   modules.backup.enable = true;
  #   modules.backup.paths = [ "/var/lib/stalwart" "/var/lib/bulwark" ];
  #   modules.backup.repository = "sftp:user@host:/srv/restic-mail";
  #   # and switch modules.sops.enable on for the repository password
}
