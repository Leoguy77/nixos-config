# Automated backups using restic
#
# Provides scheduled, deduplicated, encrypted backups via restic.
# Enable per-host and configure paths/repository through the options below.
#
# Quick start (local repository):
#   modules.backup.enable = true;
#   modules.backup.paths = [ "/home/leoguy77" "/etc/nixos" ];
#
# The repository password can be provided either via an agenix secret
# (recommended) or a plain file. See modules.backup.passwordFile.
{ config, pkgs, lib, myvars, ... }:

let
  cfg = config.modules.backup;
in
{
  options.modules.backup = {
    enable = lib.mkEnableOption "restic automated backups";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home/${myvars.username}"
      ];
      description = "List of paths to include in the backup.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home/${myvars.username}/.cache"
        "/home/${myvars.username}/.local/share/Trash"
        "/home/${myvars.username}/.mozilla/firefox/*/cache2"
        "/home/${myvars.username}/Downloads"
        "**/node_modules"
        "**/.direnv"
        "**/target"
        "**/result"
        "*.tmp"
      ];
      description = "Glob patterns to exclude from the backup.";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "/var/backup/restic";
      example = "sftp:user@host:/srv/restic-repo";
      description = ''
        Restic repository location. Can be a local path or a remote
        target (sftp, rest, s3, b2, etc.). For remote targets configure
        the relevant environment variables/credentials as well.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/restic-password";
      description = ''
        Path to a file containing the restic repository password.
        Recommended: point this at an agenix secret, e.g.
        config.age.secrets."restic-password".path.
        If null, a file is generated at /var/backup/restic-password on
        first activation (local repositories only, not encrypted at rest
        beyond file permissions).
      '';
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
      description = "systemd timer configuration controlling backup schedule.";
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 3"
      ];
      description = "Retention policy passed to `restic forget --prune`.";
    };

    initialize = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Initialize the restic repository if it does not exist.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure restic is available on the system for manual operations
    # (restore, snapshots listing, etc.).
    environment.systemPackages = [ pkgs.restic ];

    # Auto-generate a local password file when none is provided.
    # Only meaningful for local repositories; remote users should supply
    # passwordFile explicitly (ideally via agenix).
    systemd.services.restic-password-init = lib.mkIf (cfg.passwordFile == null) {
      description = "Generate restic repository password if missing";
      wantedBy = [ "multi-user.target" ];
      before = [ "restic-backups-system.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/backup
        if [ ! -f /var/backup/restic-password ]; then
          umask 077
          ${pkgs.openssl}/bin/openssl rand -base64 32 > /var/backup/restic-password
          chmod 600 /var/backup/restic-password
        fi
      '';
    };

    services.restic.backups.system = {
      inherit (cfg) paths exclude pruneOpts initialize;
      repository = cfg.repository;
      passwordFile =
        if cfg.passwordFile != null
        then cfg.passwordFile
        else "/var/backup/restic-password";
      timerConfig = cfg.timerConfig;
    };
  };
}
