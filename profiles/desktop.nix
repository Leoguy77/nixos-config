# Desktop/workstation baseline — the shared stack every graphical host enables.
#
# A desktop host picks this single import instead of typing out the ~20
# modules.* toggles by hand. Laptop-specific power management sits one level
# down in laptop.nix (which imports this); this file stays free of it so a
# desktop that never sleeps on battery can share it too.
#
# Host configs parametrize this profile with two options:
#   modules.desktop.homeModule       — path to this host's home-manager
#                                      overrides file (e.g. ./home.nix)
#   modules.desktop.backupFileExt    — optional home-manager backupFileExtension
{
  config,
  pkgs,
  inputs,
  mylib,
  myvars,
  lib,
  ...
}:

{
  options.modules.desktop = {
    homeModule = lib.mkOption {
      type = lib.types.path;
      description = "Path to this host's home-manager overrides file (its home.nix).";
    };
    backupFileExt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        home-manager backupFileExtension. When non-null, a pre-existing
        conflicting dotfile is moved to <name>.<ext> instead of failing the
        activation. Null leaves home-manager's default behaviour.
      '';
    };
  };

  config = {
    # ── Core module toggles (previously repeated in every desktop host file) ──
    modules.boot.enable = true;
    modules.boot.systemdBoot = true;
    modules.boot.efi = true;
    modules.firmware.enable = true;

    # Shared single-purpose modules every box needs.
    modules.nix.enable = true;
    modules.locale.enable = true;
    modules.locale.germanSubLocales = true;
    modules.fonts.enable = true;
    modules.networkmanager.enable = true;

    # Audio is not a desktop environment: every graphical host needs it,
    # whichever compositor draws the windows, so it stays in the shared stack.
    #
    # The DESKTOP itself (X11/Plasma, Niri, Hyprland) is no longer set here —
    # each host imports exactly one file from profiles/desktops/. Keeping it in
    # this profile made the desktop environment impossible to change without
    # editing a file every host shares.
    modules.pipewire.enable = true;

    modules.packages.enable = true;
    modules.users.enable = true;
    modules.login.enable = true;
    modules.security.enable = true;
    modules.onepassword.enable = true;

    modules.backup.enable = true;
    modules.backup.paths = [ "/home/${myvars.username}" ];
    # Off-machine, on a Hetzner Storage Box. A local repository would be the
    # disk protecting itself — on kirito it sat on the same ext4 partition as
    # /home, so the reinstall that prompted this change would have deleted the
    # data and its only copy together. host1 played this role until the box
    # replaced it.
    #
    # Each machine gets its own sub-account, and a sub-account is chrooted to
    # its home directory: this one cannot see, let alone prune, mail's snapshots.
    #
    # The port MUST live in the URL. restic's buildSSHCommand emits
    # `ssh <host> -p <port> …` from the parsed location; putting `-p 23` in
    # sftp.args instead makes restic shell-split it into the literal port
    # string "' 23 -i …'", which ssh rejects with Bad port.
    modules.backup.repository = "sftp://u726083-sub2@u726083.your-storagebox.de:23/restic-${config.networking.hostName}";

    # A non-standard port changes the known_hosts syntax too: ssh looks up the
    # bracketed form, and un-bracketed entries are ignored as "no key known".
    # hostNames is written verbatim into /etc/ssh/ssh_known_hosts, so the
    # brackets belong right here.
    modules.backup.knownHost = {
      hostNames = [ "[u726083.your-storagebox.de]:23" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
    };

    # Firmware updates via fwupd (LVFS)
    services.fwupd.enable = true;

    # Optional services are deliberately NOT enabled here. A desktop host opts
    # into each one individually (modules.<service>.enable = true) — e.g. not
    # every host needs the RDP server or SSH exposed. See laptop.nix / hosts.
    # Intentionally absent: printing, ssh, rdp, tailscale, autocpufreq.

    # ── Home-manager wrapper ──────────────────────────────────────────────
    # Identical across every desktop host except the host-specific overrides
    # file. Hoisted here so a host just points at its home.nix.
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = lib.mkIf (
        config.modules.desktop.backupFileExt != null
      ) config.modules.desktop.backupFileExt;
      extraSpecialArgs = {
        inherit
          mylib
          myvars
          inputs
          pkgs
          ;
        sops-nix = inputs."sops-nix";
      };
      users.${myvars.username} = { ... }: {
        imports = [
          ../modules/home
          config.modules.desktop.homeModule
        ];
        home.stateVersion = myvars.system.stateVersion;
      };
    };
  };
}
