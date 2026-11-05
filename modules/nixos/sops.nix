# System-level sops (sops-nix) — decrypts secrets into /run/secrets/<name>.
#
# Enabled by default so existing hosts keep working; a host that has not been
# authorised in .sops.yaml yet (e.g. a freshly installed server) must set
# `modules.sops.enable = false`, otherwise activation fails at boot because the
# age key of the machine is not a recipient of the file yet.
{ config, pkgs, lib, sops-nix, ... }:

let
  cfg = config.modules.sops;
in

{
  imports = [ sops-nix.nixosModules.sops ];

  options.modules.sops.enable = lib.mkEnableOption "system secrets via sops-nix" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = ../../secrets/secrets.sops.yaml;

      # Decrypt with the machine's SSH host key (sops-nix converts it to an age
      # identity internally, so it works even though raw age can't use host keys).
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      secrets.wg0_private_key = { };
    };
  };
}
