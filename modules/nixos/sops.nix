# System-level sops (sops-nix) — decrypts the flipdot WireGuard private key
# into /run/secrets/<name> at boot.
{ config, pkgs, lib, sops-nix, ... }:

{
  imports = [ sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.sops.yaml;

    # Decrypt with the machine's SSH host key (sops-nix converts it to an age
    # identity internally, so it works even though raw age can't use host keys).
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets.wg0_private_key = { };
  };
}
