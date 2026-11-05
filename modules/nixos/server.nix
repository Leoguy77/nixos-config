# Server baseline (no desktop).
#
# Unlike modules.system this module deliberately does NOT enable NetworkManager
# or fonts: a VPS gets a fixed address from the provider (no DHCP), and a mail
# server has no use for a desktop stack.
#
# Static networking itself lives in the host config (hosts/<name>/default.nix),
# because the addresses/gateways are provider specific.
{ config, pkgs, lib, myvars, ... }:

let
  cfg = config.modules.server;
in

{
  options.modules.server = {
    enable = lib.mkEnableOption "server baseline (no desktop, key-only SSH)";

    adminKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        SSH public keys allowed to log in as root and as {option}`modules.server.mainUser`.
        The same keys are used for the initrd SSH daemon, so this must not be
        empty on a host with an encrypted root.
      '';
    };

    mainUser = lib.mkOption {
      type = lib.types.str;
      default = myvars.username;
      description = "Administrative (wheel) user.";
    };

    initrdSsh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Remote unlock over SSH inside the initrd. The daemon is rebound to the
        tailnet address by {option}`modules.initrdTailscale` (also on by
        default), so nothing listens on the public interface.
      '';
    };

    initrdSshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Port the initrd SSH daemon (used for LUKS unlock) listens on.";
    };

    initrdSshHostKey = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Private host key for the initrd SSH daemon. Leave null (the default) to
        generate a throwaway key at build time.

        A committed key buys nothing: initrd host keys are copied into the
        world-readable nix store and onto the unencrypted /boot, so the private
        half is public either way. It only puts a private key in the git history.
        Set this only if you want a fingerprint that is stable across builds.
      '';
    };

    zramPercent = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "zram swap size as a percentage of RAM. Small VPSes need this.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Base system ────────────────────────────────────────────────────────
    system.stateVersion = lib.mkDefault myvars.system.stateVersion;
    time.timeZone = lib.mkDefault myvars.system.timeZone;
    i18n.defaultLocale = lib.mkDefault myvars.system.defaultLocale;
    console.keyMap = lib.mkDefault myvars.system.keymap;

    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        # Keep the store small: these disks are typically 20-40 GB.
        auto-optimise-store = false;
        trusted-users = [
          "root"
          cfg.mainUser
        ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
    };

    # ── Networking ─────────────────────────────────────────────────────────
    networking = {
      useNetworkd = true;
      useDHCP = false;
      nftables.enable = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22
          80
          443
        ];
        # `tailscale up --ssh` terminates in tailscaled, but admin traffic to
        # the tailnet address should not be fought over by nftables.
        trustedInterfaces = [ "tailscale0" ];
      };
      # Mail servers must not depend on MagicDNS; hosts set real resolvers.
      resolvconf.enable = false;
    };

    services.tailscale = {
      enable = true;
      # No exit node / subnet router on a mail server.
      useRoutingFeatures = "none";
      # Deliberately no extraUpFlags: this host has no auth key before the first
      # boot, and a `tailscale up` without one just fails the unit. Join once by
      # hand instead (see hosts/mail/README.md):
      #   tailscale up --ssh --accept-dns=false --advertise-tags=tag:mail
    };

    # ── Memory: 1 GB VPSes need compressed swap ────────────────────────────
    zramSwap = {
      enable = true;
      memoryPercent = cfg.zramPercent;
      priority = 100;
    };

    boot.kernel.sysctl = {
      "vm.swappiness" = 100;
      # RocksDB (Stalwart's data store) mmaps a lot.
      "vm.max_map_count" = 262144;
      "net.core.somaxconn" = 1024;
      "net.ipv4.tcp_syncookies" = 1;
    };

    services.journald.settings.Journal = {
      SystemMaxUse = "500M";
      RuntimeMaxUse = "64M";
    };

    # ── Boot loader (UEFI) ─────────────────────────────────────────────────
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.timeout = 3;
    boot.loader.systemd-boot.configurationLimit = 10;

    # ── Remote unlock: SSH daemon inside the initrd ────────────────────────
    #
    # netcup (like most VPS providers) offers no DHCP, so the initrd gets the
    # same static configuration as stage 2 (set per host).
    #
    # This sshd listens on every address by default, i.e. on the public IP for
    # the whole of stage 1 — so server hosts also enable
    # modules.initrdTailscale below, which rebinds it to the tailnet address
    # only. Both are on by default; opt out with
    #   modules.server.initrdSsh = false;        (no remote unlock at all)
    #   modules.initrdTailscale.enable = false;  (public initrd sshd)
    boot.initrd.network.enable = true;
    boot.initrd.network.ssh = lib.mkIf cfg.initrdSsh {
      enable = true;
      port = cfg.initrdSshPort;
      # A throwaway key, generated at build time. See initrdSshHostKey above.
      # The derivation output is the key file itself, not a directory: sshd's
      # HostKey needs a file and the initrd copies it to /etc/ssh/<name>.
      hostKeys = [
        (if cfg.initrdSshHostKey != null then
          cfg.initrdSshHostKey
        else
          pkgs.runCommand "initrd-ssh-host-key" { } ''
            ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" \
              -C "initrd@${config.networking.hostName}" -f $out
          '')
      ];
      extraConfig = "PermitRootLogin yes";
    };

    modules.initrdTailscale = {
      enable = lib.mkDefault cfg.initrdSsh;
      port = lib.mkDefault cfg.initrdSshPort;
    };

    # ── Accounts ───────────────────────────────────────────────────────────
    users.mutableUsers = false;

    users.users.root.openssh.authorizedKeys.keys = cfg.adminKeys;

    users.users.${cfg.mainUser} = {
      isNormalUser = true;
      description = myvars.fullName;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = cfg.adminKeys;
    };

    programs.zsh.enable = true;

    security.sudo = {
      enable = true;
      # Access is key-only and the account has no password, so a password
      # prompt would just lock the admin out.
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };

    # ── SSH ────────────────────────────────────────────────────────────────
    services.openssh = {
      enable = true;
      openFirewall = false;
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
        X11Forwarding = false;
        AllowAgentForwarding = false;
        MaxAuthTries = 3;
        ClientAliveInterval = 60;
        ClientAliveCountMax = 3;
      };
    };

    # ── Intrusion handling ─────────────────────────────────────────────────
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      ignoreIP = [
        "127.0.0.1/8"
        "::1"
      ];
      jails.sshd.settings = {
        enabled = true;
        backend = "systemd";
        findtime = "10m";
      };
    };

    # ── Basic tooling for a headless box ───────────────────────────────────
    environment.systemPackages = with pkgs; [
      btop
      curl
      git
      htop
      jq
      nano
      rsync
      tmux
      unzip
      vim
    ];
  };
}
