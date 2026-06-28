# Security settings including agenix secrets management
{ config, pkgs, lib, agenix, ... }:

let
  cfg = config.modules.security;
in

{
  options.modules.security = {
    enable = lib.mkEnableOption "security module";
    sudo = lib.mkEnableOption "sudo access for wheel group";
    enableSecrets = lib.mkEnableOption "agenix secrets management";
  };

  imports = [
    agenix.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    # Sudo configuration
    security.sudo = lib.mkIf cfg.sudo {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
    };

    # Polkit for privilege escalation
    security.polkit.enable = lib.mkDefault true;

    # Agenix secrets management
    age = lib.mkIf cfg.enableSecrets {
      # Identity keys for decrypting secrets
      # By default, uses the host's SSH keys
      identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_rsa_key"
      ];
      
      # Secrets are defined in ../secrets/secrets.nix
      # Example:
      # secrets = {
      #   "ssh-key.age".file = ../../secrets/ssh-key.age;
      #   "api-token.age".file = ../../secrets/api-token.age;
      # };
    };
  };
}
