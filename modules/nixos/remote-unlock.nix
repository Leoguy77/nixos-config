# Remote LUKS unlock over SSH in the initrd.
#
# Single purpose: let an admin unlock an encrypted root before stage 2 starts.
# Only meaningful on a host with an encrypted root. The initrd sshd is rebound
# to the tailnet address by {option}`modules.initrdTailscale` (on by default) so
# nothing listens on the public interface.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.remoteUnlock;
in

{
  options.modules.remoteUnlock = {
    enable = lib.mkEnableOption "remote LUKS unlock over SSH in the initrd";

    initrdSsh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Actually run an SSH daemon inside the initrd. Turning this off while
        still enabling remoteUnlock leaves the initrd network up but with no
        way into it.
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
  };

  config = lib.mkIf cfg.enable {
    # netcup (like most VPS providers) offers no DHCP, so the initrd gets the
    # same static configuration as stage 2 (set per host in hosts/<name>).
    boot.initrd.network.enable = true;
    boot.initrd.network.ssh = lib.mkIf cfg.initrdSsh {
      enable = true;
      port = cfg.initrdSshPort;
      # A throwaway key, generated at build time. See initrdSshHostKey above.
      # The derivation output is the key file itself, not a directory: sshd's
      # HostKey needs a file and the initrd copies it to /etc/ssh/<name>.
      hostKeys = [
        (
          if cfg.initrdSshHostKey != null then
            cfg.initrdSshHostKey
          else
            pkgs.runCommand "initrd-ssh-host-key" { } ''
              ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" \
                -C "initrd@${config.networking.hostName}" -f $out
            ''
        )
      ];
      # Root only, unlike stage 2 (which sets PermitRootLogin = "no"). Not an
      # oversight — there is no other account that can do anything here:
      #   - the initrd has no sudo and this sshd sets `UsePAM no`, so a
      #     non-root login could not escalate to the uid-0 operations below;
      #   - both unlock paths need uid 0: `systemd-tty-ask-password-agent`
      #     watches /run/user/0/systemd/ask-password, and `systemd-cryptsetup`
      #     opens a keyslot on the real block device;
      #   - `boot.initrd.network.ssh` writes exactly one authorized-keys file,
      #     /etc/ssh/authorized_keys.d/root.
      # Exposure is bounded by modules.initrdTailscale below: tailnet address
      # only, port 2222, tag:fde-unlock. Never public.
      extraConfig = "PermitRootLogin yes";
    };

    modules.initrdTailscale = {
      enable = lib.mkDefault cfg.initrdSsh;
      port = lib.mkDefault cfg.initrdSshPort;
    };
  };
}
