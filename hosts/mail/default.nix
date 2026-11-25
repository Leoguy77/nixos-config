# netcup VPS (pico G11s) — mail.lsinfra.de
#
# Postfix + Dovecot + rspamd + Roundcube, all declared in ./modules/nixos/mail.nix.
# LUKS-encrypted root unlocked over SSH in the initrd. See ./README.md for the
# deployment runbook.
{
  config,
  lib,
  pkgs,
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
    ../../profiles/disk/luks-btrfs-server.nix
    ./hardware-configuration.nix
    # The lsinfra.de zone, as declared records. Split by owning machine: mail
    # publishes, but asuna's records are declared next to asuna.
    ./dns.nix
    ../asuna/dns.nix
    # Server role: composes the narrow server modules (remote LUKS unlock,
    # key-only SSH, zram, fail2ban) into a baseline. Enables them via
    # profiles/server.nix.
    ../../profiles/server.nix
  ];

  # ── Server baseline (no desktop) ─────────────────────────────────────────
  # The role profile (profiles/server.nix) switches on the narrow server
  # modules; here we only supply the host-specific admin identity.
  modules.accounts.adminKeys = [
    # One line covers every Token2 token: the OpenPGP auth subkey. Plus the
    # legacy 1Password key as a fallback for a machine with no card reader.
    myvars.ssh.key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMeOpEP8l Github"
  ];

  # The initrd host key is generated at build time (module default). A
  # committed one would be public either way — it lands in the world-readable
  # nix store and on the unencrypted /boot — so it only ever put a private key
  # in the git history without buying any secrecy.

  # Initrd SSH must never be reachable from the internet. That is handled by
  # modules.remoteUnlock, which enables modules.initrdTailscale on every server
  # host: tailscaled joins from the initrd (identity persisted on the ESP) and
  # sshd binds the tailnet address only. No per-host wiring, no auth key once
  # joined.

  # ── Mail stack ───────────────────────────────────────────────────────────
  modules.mail.enable = true;
  modules.mail.hostname = "mail.lsinfra.de";
  modules.mail.webmailHostname = "webmail.lsinfra.de";
  modules.mail.domain = "lsinfra.de";
  modules.mail.acmeEmail = myvars.email;

  # Password hash, not a plaintext password: `mkpasswd -m sha-512`. It lives in
  # sops so the account exists at the end of the install with no console step.
  # A hash is still a credential, but one that cannot be replayed.
  modules.mail.accounts.leon.hashedPasswordFile = config.sops.secrets.leon_password_hash.path;

  # Aggregate DMARC reports (`rua` in hosts/mail/dns.nix) go to postmaster, which
  # aliases to leon. File them separately so they don't bury real mail.
  # Matches `x-original-to` because Postfix rewrites the envelope during alias
  # expansion; matching on `to` would break if a reporter omitted that header.
  modules.mail.accounts.leon.sieveScript = ''
    require ["fileinto"];

    if address :is ["to", "x-original-to"] "postmaster@lsinfra.de" {
      fileinto "DMARC";
      stop;
    }
  '';

  # ── DNS ──────────────────────────────────────────────────────────────────
  # This host publishes the lsinfra.de zone. Records themselves live in
  # ./dns.nix; the registry is open to every module in the tree via
  # `mylib.publishDns`, and `push.enable` is the single thing that decides who
  # talks to Cloudflare.
  modules.dns.push.enable = true;
  modules.dns.push.zone = "lsinfra.de";

  # A push deletes anything not in the record list. The only records this repo
  # must not own are the ACME challenge TXT records, written by whatever is
  # currently renewing a cert.
  modules.dns.push.ignore = [ ''IGNORE_NAME("_acme-challenge.**")'' ];

  # host1's address, injected from sops at push time because this repo is public.
  modules.dns.push.variables = {
    host1_ipv4.secret = "host1_ipv4";
    host1_ipv6 = {
      secret = "host1_ipv6";
      placeholder = "2001:db8::1";
    };
  };

  # Secrets via sops-nix. This host declares several (dkim, the account password,
  # the DNS token), so it MUST be a recipient in .sops.yaml — otherwise activation
  # cannot decrypt and those consumers get an empty file. Its identity is the SSH
  # host key, which `scripts/deploy.sh` mints on the control machine and enrols
  # here automatically before the install; the private half never leaves the box.
  modules.sops.enable = true;

  # ── Identity ─────────────────────────────────────────────────────────────
  networking = {
    hostName = "mail";
    domain = "lsinfra.de";
    nameservers = [
      "9.9.9.9"
      "149.112.112.112"
      "2620:fe::fe"
    ];
  };

  systemd.network.networks."10-wan" = wan;
  boot.initrd.systemd.network.networks."10-wan" = wan;

  # ── Hardware ─────────────────────────────────────────────────────────────
  # KVM guest: nothing to import, no microcode/firmware blobs of our own.
  hardware.enableRedistributableFirmware = lib.mkDefault false;

  # ── Operations ───────────────────────────────────────────────────────────
  # Daily rebuild from GitHub. Safe again now: no secret is needed to build this
  # host (the initrd tailscale node state lives on the machine's own ESP).
  # allowReboot = false: a reboot means unlocking the disk over the tailnet.
  #
  # hourly, not daily: there is one shared flake.lock and CI refreshes it on its
  # own schedule, so a daily poll here wastes up to a full day on top of the day
  # CI can already take. GitHub's scheduler is also late by hours (see the
  # update-flake-lock workflow), which a fixed time cannot align with. Polling
  # every hour makes that jitter irrelevant: the run that finds a new commit does
  # the switch, the other 23 are a no-op rebuild (measured: 9 s).
  system.autoUpgrade = {
    enable = true;
    flake = "github:Leoguy77/nixos-config#mail";
    dates = "hourly";
    persistent = true;
    allowReboot = false;
  };

  # The flake tarball is cached per machine and only revalidated hourly. That is
  # fine for a pull, but this box upgrades unattended: a stale tarball means it
  # rebuilds the commit it already has and reports success. Flakes are cheap to
  # re-fetch and the lock pins every input, so the cache buys nothing here.
  nix.settings.tarball-ttl = 0;

  # Backups to the Hetzner Storage Box, sub-account `u726083-sub1`. That
  # sub-account is chrooted to its home, so it cannot read or prune kirito's
  # snapshots, and deleting it revokes only this machine.
  #
  # The mail store is the one dataset here that cannot be recreated: DKIM keys
  # sign outbound mail, and losing them invalidates every published selector.
  #
  # The port must live in the URL; see profiles/desktop.nix for why sftp.args
  # cannot carry it. The bracketed hostNames form is the non-standard-port
  # syntax ssh actually consults.
  modules.backup.enable = true;
  modules.backup.paths = [
    "/var/vmail"
    "/var/lib/roundcube"
    "/var/lib/dkim"
    "/var/backup/roundcube-db"
  ];
  modules.backup.backupPrepareCommand = ''
    # Roundcube's attachments, identities and contacts live in postgres, not
    # in /var/lib/roundcube, so a file-level backup would restore a webmail
    # that has forgotten every message it ever indexed. Dumped every run: the
    # database is small, and a backup needing a second, differently-scheduled
    # job to be complete is one that silently is not.
    #
    # As the `roundcube` role, not root: with database.host = "localhost" the
    # module creates that role for peer auth, and root is not a postgres
    # superuser here. `sudo -u` picks up the matching unix user, so no password
    # is involved anywhere.
    mkdir -p /var/backup/roundcube-db
    ${pkgs.sudo}/bin/sudo -u roundcube ${config.services.postgresql.package}/bin/pg_dump \
      --clean --if-exists roundcube > /var/backup/roundcube-db/roundcube.sql
  '';
  modules.backup.repository = "sftp://u726083-sub1@u726083.your-storagebox.de:23/restic-${config.networking.hostName}";
  modules.backup.knownHost = {
    hostNames = [ "[u726083.your-storagebox.de]:23" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
  };
}
