# Home-manager sops (sops-nix) — decrypts the pi HA MCP config with the
# user's SSH key (~/.ssh/GPG), converted to PGP internally via ssh-to-pgp.
# Writes ~/.pi/agent/mcp.json (sops-install-secrets makes the parent dir).
{ config, pkgs, lib, sops-nix, ... }:

let
  cfg = config.modules.home.sops;
  home = config.home.homeDirectory;
in
{
  options.modules.home.sops.enable = lib.mkEnableOption "sops-nix secrets (home-manager)";

  imports = [ sops-nix.homeManagerModules.sops ];

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = ../../secrets/secrets.sops.yaml;

      # Decrypt pi's mcp.json with the user's ssh-RSA key (converted to PGP).
      gnupg.sshKeyPaths = [ "${home}/.ssh/GPG" ];

      secrets.pi_mcp_json = {
        path = "${home}/.pi/agent/mcp.json";
      };
    };
  };
}
