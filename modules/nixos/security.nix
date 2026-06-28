# Security settings
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.security;
in

{
  options.modules.security = {
    enable = lib.mkEnableOption "security module";
    sudo = lib.mkEnableOption "sudo access for wheel group";
  };

  config = lib.mkIf cfg.enable {
    # Sudo configuration
    security.sudo = lib.mkIf cfg.sudo {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
    };

    # Polkit for privilege escalation
    security.polkit.enable = lib.mkDefault true;
  };
}
