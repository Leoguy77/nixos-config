# Desktop SSH server (key-only, no root).
#
# Single purpose: SSH access to a desktop/laptop on the home LAN. Deliberately
# NOT the same policy as sshd.nix — that is the hardened server daemon
# (AllowUsers, forwarding off, grace-timeout, explicit host keys). A desktop
# wants the NixOS defaults plus key-only auth.
{
  config,
  lib,
  ...
}:

{
  options.modules.ssh = {
    enable = lib.mkEnableOption "the desktop SSH server";
  };

  config = lib.mkIf config.modules.ssh.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = lib.mkDefault "no";
      };
    };
  };
}
