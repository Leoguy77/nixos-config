# Tailscale inside the initrd — remote LUKS unlock without exposing SSH.
#
# Without this, the initrd SSH daemon listens on the *public* address for as long
# as the machine sits in stage 1, which is exactly the window an attacker would
# want. Here tailscaled joins the tailnet from the initrd and sshd binds to the
# tailnet address **only**; nothing listens on the public interface at all.
#
# How it hangs together:
#   tailscaled (state in RAM, so the node is ephemeral)
#     └─ tailscale up --auth-key=…  (oneshot)
#          └─ sshd -o ListenAddress=<tailnet ip>   ← bind happens at runtime
#
# If the tailnet never comes up, the bind script exits non-zero and systemd
# retries — sshd is never started with a public listen address. Fail closed.
#
# Caveats worth knowing:
#   - The auth key lives in the initrd image on the unencrypted /boot, like the
#     initrd host key. Use a short-lived *ephemeral*, tagged, pre-approved key.
#   - tailscaled re-registers on every boot, so the node name can briefly be
#     suffixed (mail-initrd-1) right after a reboot. Check `tailscale status`.
#   - This host cannot be rebuilt by GitHub autoUpgrade if the key file is not
#     committed (see hosts/mail/README.md).
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.initrdTailscale;

  tailscale = config.services.tailscale.package;
  sshPkg = config.programs.ssh.package;

  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # The bootstrap key lives on the ESP, next to the persisted node state, NOT as
  # a build input. As a build input it was a `builtins.pathExists` on a gitignored
  # file, so any rebuild from a checkout without it produced a keyless initrd and
  # silently overwrote a working /boot. Anything the initrd needs in order to be
  # unlockable must survive a rebuild, so it lives on the disk instead.
  authKeyPath = "${cfg.stateMountPoint}/tailscale-authkey";

  # Assembled here so the generated script never ends in a dangling backslash
  # when extraUpFlags is empty.
  upFlags = [
    "--hostname=${config.networking.hostName}-initrd"
    "--auth-key=file:${authKeyPath}"
    "--netfilter-mode=off"
    "--accept-dns=false"
    "--accept-routes=false"
  ]
  ++ cfg.extraUpFlags;

  # Bind sshd to whatever address tailscaled handed us, or fail (systemd
  # retries after RestartSec). No polling loop, no `sleep`, no external tools.
  bindScript = ''
    #!${pkgs.runtimeShell}
    set -u
    sock=/run/tailscale/tailscaled.sock
    nl=$'\n'
    ip="$(${tailscale}/bin/tailscale --socket="$sock" ip -4 2>/dev/null || true)"
    # Keep only the first line (bash-only: no head/cut available in the initrd).
    ip="''${ip%%"$nl"*}"
    if [ -z "$ip" ]; then
      echo "initrd-sshd: no tailnet address yet — not binding any listen address" >&2
      exit 1
    fi
    echo "initrd-sshd: listening only on $ip:${toString cfg.port}"
    exec ${sshPkg}/bin/sshd -D -f /etc/ssh/sshd_config -o "ListenAddress=$ip"
  '';
in

{
  options.modules.initrdTailscale = {
    enable = lib.mkEnableOption "tailnet-only initrd SSH for remote LUKS unlock";

    port = lib.mkOption {
      type = lib.types.port;
      default = config.boot.initrd.network.ssh.port;
      defaultText = lib.literalExpression "config.boot.initrd.network.ssh.port";
      description = "Port the initrd sshd listens on (on the tailnet address only).";
    };

    stateMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/run/initrd-boot";
      description = ''
        Where the ESP is mounted inside the initrd to hold the tailscaled state.
        Deliberately *not* /boot: stage 2 mounts the ESP there, and mounting one
        device at two paths across switch-root invites confusion.
      '';
    };

    stateDevice = lib.mkOption {
      type = lib.types.str;
      default = config.fileSystems."/boot".device;
      defaultText = lib.literalExpression ''config.fileSystems."/boot".device'';
      description = ''
        Unencrypted device holding the tailscaled state — it must be readable
        before the root is unlocked, which is the whole point.
      '';
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.stateMountPoint}/tailscale-initrd.state";
      defaultText = lib.literalExpression ''"''${stateMountPoint}/tailscale-initrd.state"'';
      description = ''
        Persistent node state. This is what replaces an expiring auth key: the node
        registers once and keeps its identity (and its 100.x address) across
        reboots.
      '';
    };

    extraUpFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--advertise-tags=tag:mail-initrd" ];
      description = "Extra arguments for `tailscale up` inside the initrd.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.network.ssh.enable;
        message = "modules.initrdTailscale expects boot.initrd.network.ssh.enable = true.";
      }
    ];

    boot.initrd.kernelModules = [ "tun" ];
    boot.initrd.availableKernelModules = [ "tun" ];

    # The mount below is a vfat ESP. NixOS only pulls a filesystem's kernel
    # module into the initrd when its type is listed here, and the default list
    # is derived from the `neededForBoot` mounts — /boot is not one of them.
    # Without this the mount fails every boot with
    # "Failed to mount /run/initrd-boot" and tailscaled gets no state dir.
    # iso-image.nix sets this for the same reason.
    boot.initrd.supportedFilesystems = [ "vfat" ];

    # The ESP is unencrypted, so it can hold the tailscaled state from the very
    # start of stage 1.
    boot.initrd.systemd.mounts = [
      {
        what = cfg.stateDevice;
        where = cfg.stateMountPoint;
        type = "auto";
        options = "rw,fmask=0077,dmask=0077";
        wantedBy = [ "initrd.target" ];
        before = [ "tailscaled.service" ];
        unitConfig.DefaultDependencies = false;
        # Initrd units must state their start ratelimit explicitly (no defaults).
        # 0 = unlimited.
        startLimitBurst = 0;
        startLimitIntervalSec = 0;
      }
    ];

    boot.initrd.systemd.storePaths = [
      "${tailscale}/bin/tailscaled"
      "${tailscale}/bin/tailscale"
      "${sshPkg}/bin/sshd"
      "${pkgs.bash}/bin/bash"
      caBundle
    ];

    boot.initrd.systemd.contents = {
      # tailscaled speaks TLS to the control plane and needs a trust store.
      "/etc/ssl/certs/ca-certificates.crt".source = caBundle;
      "/etc/initrd-sshd-tailnet.sh".text = bindScript;
    };

    boot.initrd.systemd.services.tailscaled = {
      description = "Tailscale daemon (initrd)";
      wantedBy = [ "initrd.target" ];
      after = [
        "network.target"
        "initrd-nixos-copy-secrets.service"
      ];
      # Must start before the encrypted root is unlocked.
      unitConfig.DefaultDependencies = false;
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      serviceConfig = {
        Type = "notify";
        RuntimeDirectory = "tailscale";
        # State lives on the (unencrypted) ESP, so the node keeps its identity
        # and its tailnet address across reboots and never needs re-auth.
        ExecStart = "${tailscale}/bin/tailscaled --state=${cfg.stateFile} --statedir=/run/tailscale --socket=/run/tailscale/tailscaled.sock --netfilter-mode=off";
        Environment = [ "SSL_CERT_FILE=${caBundle}" ];
        # Degraded fallback: if the ESP mount failed, tailscaled still starts with
        # an ephemeral state dir on tmpfs instead of taking the whole unlock path
        # down with it. Costs the persisted node identity (needs a fresh auth key
        # next boot), which beats "cannot unlock at all".
        #
        # Absolute store path on purpose: the initrd has no /bin, so a bare
        # `mkdir` fails 203/EXEC and takes tailscaled down with it — which breaks
        # the join silently while the rest of the boot looks healthy.
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.stateMountPoint}";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    boot.initrd.systemd.services.tailscaled-autoconnect = {
      description = "Join the tailnet (initrd, bootstrap only)";
      wantedBy = [ "initrd.target" ];
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      unitConfig = {
        DefaultDependencies = false;
      };
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [ "SSL_CERT_FILE=${caBundle}" ];
      };
      script = ''
        ts=${tailscale}/bin/tailscale
        sock=/run/tailscale/tailscaled.sock

        # The key is on the ESP, written there once by scripts/deploy.sh. It is
        # deliberately not a build input: a keyless rebuild must not be able to
        # strip the machine's ability to unlock itself over the tailnet. After a
        # successful join the persisted state makes the key unnecessary.
        [ -f ${authKeyPath} ] || exit 0

        # Already joined (persisted state) — `tailscale up` again would fail.
        if "$ts" --socket="$sock" status >/dev/null 2>&1; then
          exit 0
        fi

        exec "$ts" --socket="$sock" up ${lib.escapeShellArgs upFlags}
      '';
    };

    # Replace the stock initrd sshd start with the tailnet-only bind.
    boot.initrd.systemd.services.sshd = {
      after = [ "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled-autoconnect.service" ];
      serviceConfig = {
        ExecStart = lib.mkForce "${pkgs.bash}/bin/bash /etc/initrd-sshd-tailnet.sh";
        RestartSec = 10;
      };
    };
  };
}
