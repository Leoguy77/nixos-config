# Home-manager sops (sops-nix) — decrypts the pi HA MCP config with the
# user's Token2 GPG card (Leon's master 23CDB62B…, subkeys on the hardware
# keys). Writes ~/.pi/agent/mcp.json (sops-install-secrets makes the parent
# dir). Decryption requires a Token2 plugged in (OpenPGP applet) + PIN.
{
  config,
  lib,
  sops-nix,
  ...
}:

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

      secrets.pi_mcp_json = {
        path = "${home}/.pi/agent/mcp.json";
      };
    };
  };
}
