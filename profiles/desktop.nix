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
  pkgs-stable,
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

    # The desktop stack: display server, desktop environment, audio.
    modules.x11.enable = true;
    modules.plasma.enable = true;
    modules.pipewire.enable = true;

    modules.packages.enable = true;
    modules.users.enable = true;
    modules.security.enable = true;
    modules.onepassword.enable = true;

    modules.backup.enable = true;
    modules.backup.paths = [ "/home/${myvars.username}" ];
    # Off-machine, on host1 (ts.aero-gaming.de). Per-host directory so a second
    # desktop can share the box without mixing snapshot sets or retention.
    #
    # A local repository would be the disk protecting itself — on kirito it sat
    # on the same ext4 partition as /home, so the reinstall that prompted this
    # change would have deleted the data and its only copy together.
    modules.backup.repository = "sftp:leoguy77@host1:/home/leoguy77/restic-repo/${config.networking.hostName}";
    modules.backup.knownHost = {
      hostNames = [
        "host1"
        "host1.tail4628f.ts.net"
        "ts.aero-gaming.de"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIaqFLlTS/8HWt06khHhXeNwSLXC54uCVj2zHeD/Ol+2";
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
          pkgs-stable
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
