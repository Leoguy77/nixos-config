# Hardened stage-2 SSH server.
#
# Single purpose: the sshd that runs on the real (stage-2) system. It is
# intentionally separate from the initrd unlock daemon (remote-unlock.nix):
# different threat model, different config, and only servers need this one.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.sshd;
in

{
  options.modules.sshd = {
    enable = lib.mkEnableOption "the hardened stage-2 SSH server";

    mainUser = lib.mkOption {
      type = lib.types.str;
      default = config.modules.accounts.mainUser;
      description = "The only user allowed to log in via SSH.";
    };
  };

  config = lib.mkIf cfg.enable {
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
        # No root login. It granted nothing: the admin account is in `wheel`
        # with passwordless sudo, so root-by-key was a second door to the same
        # room — one that leaves no sudo record of what was run and adds an
        # always-existent uid 0 to the username surface.
        #
        # The initrd sshd is unaffected: boot.initrd.network.ssh builds its own
        # sshd_config and never inherits this.
        PermitRootLogin = "no";
        X11Forwarding = false;
        AllowAgentForwarding = false;
        # Nothing on a server needs to tunnel through sshd — Tailscale carries
        # its own traffic via tailscaled, not through an SSH session.
        AllowTcpForwarding = false;
        MaxAuthTries = 3;
        # One authenticated connection may run several channels (muxing), so
        # this only caps the abusive case.
        MaxSessions = 3;
        ClientAliveInterval = 60;
        ClientAliveCountMax = 3;

        # Only the administrative account may log in.
        AllowUsers = [ cfg.mainUser ];
        # Spelled out rather than left implicit: if any future change enables
        # password or kbd-interactive auth, this still refuses to accept it.
        AuthenticationMethods = "publickey";

        # Nothing consumes ~/.ssh/rc — it is only a hook for arbitrary
        # commands on login, so the safe default is off.
        PermitUserRC = false;
        # Unix-socket forwarding is a lateral-movement primitive and no client
        # of this box needs it.
        AllowStreamLocalForwarding = false;

        # An unauthenticated connection holds a slot for LoginGraceTime; the
        # stock 2 minutes is a free amplification target for a slow-loris.
        LoginGraceTime = "30s";
      };
    };
  };
}
