# Security settings (sudo, polkit, seccomp)
# Agenix secrets moved to modules/nixos/secrets.nix
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.security;
in

{
  options.modules.security = {
    enable = lib.mkEnableOption "security module";
    sudo = lib.mkEnableOption "sudo access for wheel group";
    enableSecrets = lib.mkEnableOption "agenix secrets management (old alias, use modules.secrets)";
  };

  config = lib.mkIf cfg.enable {
    # Sudo configuration
    security.sudo = lib.mkIf cfg.sudo {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
    };

    # Polkit for privilege escalation
    security.polkit.enable = lib.mkDefault true;

    # Forward old enableSecrets to the new secrets module
    modules.secrets.enable = lib.mkDefault cfg.enableSecrets;
  };
}
