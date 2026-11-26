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

  # Maintenance units must talk to the same repository as the backup itself, so
  # they inherit its environment (RESTIC_REPOSITORY, RESTIC_PASSWORD_FILE,
  # RESTIC_CACHE_DIR) instead of duplicating it. `restic-system` is a wrapper
  # built by the upstream module from that same environment, so invoking it
  # here would mean guessing at a store path; carrying the env and the package
  # explicitly is direct.
  resticPackage = config.services.restic.backups.system.package;

  # Same `-o` restic is given by the backup unit. Without it the sftp backend
  # has no key and every maintenance run fails to authenticate.
  resticExtraOptions = lib.optionals (cfg.sshKeyFile != null) [
    "sftp.args=-i ${cfg.sshKeyFile} -o IdentitiesOnly=yes"
  ];

  resticMaintenance = pkgs.writeShellScript "restic-maintenance" ''
    set -eu
    exec ${lib.getExe resticPackage} \
      ${lib.concatMapStrings (arg: "-o ${lib.escapeShellArg arg} ") resticExtraOptions}\
      "$@"
  '';
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
      description = ''
        Retention policy passed to `restic forget --prune` by the weekly
        prune timer.

        Deliberately NOT applied on every backup: `prune` rewrites pack files
        and took ~50s for 358 packs at 5 GiB, so running it nightly makes the
        backup job as slow as the prune. Empty it to disable pruning entirely.
      '';
    };

    pruneTimerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      description = "systemd timer configuration controlling pruning.";
    };

    checkOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Metadata alone proves the index is consistent, not that the pack files
      # still hold the data. A subset read spreads a full verification over
      # ~10 weeks without making any single run slow. Set to [ ] for a
      # structure-only check.
      default = [ "--read-data-subset=10%" ];
      description = "Options for the scheduled `restic check`.";
    };

    checkTimerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      description = "systemd timer configuration controlling repository checks.";
    };

    unlockBeforeBackup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `restic unlock` before each backup.

        restic holds an exclusive lock for a whole run. When a process is killed
        — a cancelled check, a suspend, an OOM — the lock survives and every
        later run dies with `repository is already locked`. Upstream used to
        clear that as a side effect of the `unlock` it ran inside its prune
        block; with pruning moved out, nothing does it any more.

        `unlock` only drops locks whose owning process is gone, so a genuine
        concurrent run is never disturbed.
      '';
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
        initialize
        ;
      inherit (cfg) repository;

      # No pruneOpts: upstream appends `forget --prune` to the backup unit's own
      # ExecStart, which is why retention used to cost the nightly run minutes.
      # Pruning lives on its own weekly timer below, and the `unlock` that came
      # with that block is restored explicitly — see `unlockBeforeBackup`.
      backupPrepareCommand =
        if cfg.backupPrepareCommand != null then
          ''
            ${lib.optionalString cfg.unlockBeforeBackup "${resticMaintenance} unlock || true"}
            ${cfg.backupPrepareCommand}
          ''
        else
          lib.optionalString cfg.unlockBeforeBackup "${resticMaintenance} unlock || true";

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

    # Maintenance that must not lengthen the nightly backup: both run through
    # the `restic-system` wrapper, so they inherit the same repository, password
    # and ssh key with no second copy of any of it.
    systemd.services.restic-maintenance-prune = lib.mkIf (cfg.pruneOpts != [ ]) {
      description = "Drop snapshots past the retention policy and reclaim space";
      after = [
        "network-online.target"
        "restic-backups-system.service"
      ];
      wants = [ "network-online.target" ];
      path = [ config.programs.ssh.package ];
      environment = config.systemd.services.restic-backups-system.environment;
      serviceConfig = {
        Type = "oneshot";
        # forget drops the references (cheap); prune rewrites packs (slow).
        # They are one unit so a prune never runs against a policy change
        # that was decided but not applied.
        ExecStart = pkgs.writeShellScript "restic-prune" ''
          set -eu
          ${resticMaintenance} unlock || true
          ${resticMaintenance} forget ${lib.concatStringsSep " " cfg.pruneOpts}
          ${resticMaintenance} prune
        '';
        CacheDirectory = "restic-backups-system";
        CacheDirectoryMode = "0700";
        # A prune interrupted halfway can leave the index mid-rewrite; restic
        # recovers on the next run, and a retry is cheap compared to a backup
        # that never gets its retention applied.
        Restart = "on-failure";
        RestartSec = "30min";
      };
      startLimitIntervalSec = 7200;
      startLimitBurst = 3;
    };

    systemd.timers.restic-maintenance-prune = lib.mkIf (cfg.pruneOpts != [ ]) {
      wantedBy = [ "timers.target" ];
      timerConfig = cfg.pruneTimerConfig;
    };

    # Nothing else verifies that the pack files still contain the data they
    # claim to. Without this a corrupted repository looks healthy until the day
    # a restore is attempted.
    systemd.services.restic-maintenance-check = {
      description = "Verify the restic repository";
      after = [
        "network-online.target"
        "restic-backups-system.service"
      ];
      wants = [ "network-online.target" ];
      path = [ config.programs.ssh.package ];
      environment = config.systemd.services.restic-backups-system.environment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${resticMaintenance} check ${lib.concatStringsSep " " cfg.checkOpts}";
        CacheDirectory = "restic-backups-system";
        CacheDirectoryMode = "0700";
        # A check downloads real pack data, so it can fail on a flaky link just
        # as easily as on corruption. Retrying distinguishes the two.
        Restart = "on-failure";
        RestartSec = "30min";
      };
      startLimitIntervalSec = 7200;
      startLimitBurst = 3;
    };

    systemd.timers.restic-maintenance-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = cfg.checkTimerConfig;
    };
  };
}
