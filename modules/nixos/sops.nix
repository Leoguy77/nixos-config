# System-level sops (sops-nix) — decrypts the flipdot WireGuard private key
# into /run/secrets/<name> at boot.
{ config, pkgs, lib, sops-nix, ... }:

{
  imports = [ sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.sops.yaml;

    # Same age identity the home sops config uses (root reads it at activation).
    age.keyFile = "/home/leoguy77/.config/sops/age/keys.txt";

    secrets.wg0_private_key = { };
  };
}
