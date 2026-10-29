# Home-manager sops (sops-nix) — decrypts secrets into ~/.config/sops-nix/secrets/.
# The pi HA MCP config is written straight to ~/.pi/agent/mcp.json (sops-install-secrets
# creates the parent dir itself), so pi picks it up with no extra service.
{ config, pkgs, lib, sops-nix, ... }:

let
  cfg = config.modules.home.sops;
in
{
  options.modules.home.sops.enable = lib.mkEnableOption "sops-nix secrets (home-manager)";

  imports = [ sops-nix.homeManagerModules.sops ];

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = ../../secrets/secrets.sops.yaml;

      # Decryption identity: the age key managed locally for sops.
      # BACKUP ~/.config/sops/age/keys.txt — losing it loses decryption.
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      secrets = {
        # Value is the full .pi/agent/mcp.json; path writes it in place.
        pi_mcp_json = {
          path = "${config.home.homeDirectory}/.pi/agent/mcp.json";
        };
      };
    };
  };
}
