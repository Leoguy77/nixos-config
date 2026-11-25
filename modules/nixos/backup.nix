# Automated backups using restic
#
# Provides scheduled, deduplicated, encrypted backups via restic.
# Enable per-host and configure paths/repository through the options below.
#
# Quick start (local repository):
#   modules.backup.enable = true;
#   modules.backup.paths = [ "/home/leoguy77" "/etc/nixos" ];
#
# The repository password can be provided either via a sops secret
# (recommended) or a plain file. See modules.backup.passwordFile.
{
  config,
  pkgs,
  lib,
  myvars,
  ...
}:

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

    sshKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # Reads `restic_ssh_key`, which `modules/nixos/sops.nix` binds to a
      # per-host file. The isolation comes from that file's recipient list, not
      # from the secret's name: the shared secrets file is readable by every
      # host, so a key stored there is readable by all of them regardless of
      # what it is called.
      default =
        if config.modules.sops.enable && config.sops.secrets ? restic_ssh_key then
          config.sops.secrets.restic_ssh_key.path
        else
          null;
      defaultText = lib.literalExpression "config.sops.secrets.restic_ssh_key.path";
      example = "config.sops.secrets.\"restic_ssh_key\".path";
      description = ''
        Private key restic uses to reach an `sftp:` repository.

        A dedicated key, not the user's own: it only needs to read one
        directory on one host, so restrict it on the far side
        (`restrict ssh-ed25519 AAAA… restic`) and it cannot be reused
        elsewhere. Leaking it costs a repository, not a shell.

        Host verification uses `programs.ssh.knownHosts`, which writes the
        global `/etc/ssh/ssh_known_hosts`. Pinning the fingerprint in the flake
        beats TOFU state in root's home, which a reinstall would lose anyway.
      '';
    };

    knownHost = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            hostNames = lib.mkOption { type = lib.types.listOf lib.types.str; };
            publicKey = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = null;
      description = ''
        The repository host's ed25519 host key, pinned into
        `/etc/ssh/ssh_known_hosts`. Without it the first backup stops on an
        unknown-host prompt that a systemd timer can never answer.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "config.sops.secrets.\"restic_password\".path";
      description = ''
        Path to a file containing the restic repository password.
        Point this at a sops secret, e.g.
        `config.sops.secrets."restic_password".path`.

        If null, the sops `restic_password` is used when sops is enabled;
        otherwise a password is generated at /var/backup/restic-password on
        first activation. That generated file is NOT reproducible from the
        flake, so a reinstall or an ephemeral root destroys it — and every
        snapshot in the repository with it. Leave this null only for throwaway
        repositories.
      '';
    };

    backupPrepareCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Shell fragment run immediately before `restic backup`, as root.

        Exists for directories created at start-up, which are therefore absent
        on a fresh boot: restic fails the entire run when a path in `paths` does
        not exist. Create them here rather than pre-creating them on disk, which
        an ephemeral root would not keep anyway.
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

    # Pin the repository host's key. One global attrset keyed by name, so hosts
    # sharing a repository simply set the same entry.
    programs.ssh.knownHosts = lib.mkIf (cfg.knownHost != null) {
      restic-repository = {
        inherit (cfg.knownHost) hostNames publicKey;
      };
    };

    # Fallback for scratch repositories. The generated value exists only on this
    # machine, so it cannot survive a reinstall or an ephemeral root, and the
    # snapshots it encrypts die with it. A real backup sets passwordFile to a
    # sops secret.
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
      inherit (cfg)
        paths
        exclude
        pruneOpts
        initialize
        backupPrepareCommand
        ;
      inherit (cfg) repository;

      # One of these two is always set: `passwordFile` when given, the sops
      # secret next, and restic-password-init handles the remainder.
      passwordFile =
        if cfg.passwordFile != null then
          cfg.passwordFile
        else if config.modules.sops.enable && config.sops.secrets ? restic_password then
          config.sops.secrets.restic_password.path
        else
          "/var/backup/restic-password";

      # sftp is driven by restic's own ssh invocation, so the key is passed as
      # `-o sftp.args=…` rather than written into root's ssh config. Host
      # verification needs nothing here: ssh reads the global
      # `/etc/ssh/ssh_known_hosts` by default, which `programs.ssh.knownHosts`
      # populates from `cfg.knownHost` above.
      extraOptions = lib.optionals (cfg.sshKeyFile != null) [
        "sftp.args='-i ${cfg.sshKeyFile} -o IdentitiesOnly=yes'"
      ];

      inherit (cfg) timerConfig;
    };

    # restic's unit already declares `after = [ "network-online.target" ]`, but
    # that target stays "reached" across a suspend/resume, so it guarantees
    # nothing on the wake-from-sleep path — which is exactly when this fires.
    # With `Persistent = true`, systemd runs the missed daily job immediately on
    # resume, and DNS was still down: "Could not resolve hostname
    # u726083.your-storagebox.de". The backup is the one timer that must not be
    # allowed to silently skip a day, so retry instead of losing the run.
    #
    # Bounded by startLimit*: six attempts over two hours, then it gives up and
    # waits for the next timer activation rather than retrying all day.
    systemd.services.restic-backups-system = {
      startLimitIntervalSec = 7200;
      startLimitBurst = 6;
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "15min";
      };
    };
  };
}
