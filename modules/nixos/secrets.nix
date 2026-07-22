# NixOS agenix secrets — wires global/ + machine/<host>/ tiers
{ config, pkgs, lib, agenix, myvars, ... }:

let
  cfg = config.modules.secrets;
  secretsData = import ../../secrets/secrets.nix { inherit myvars; };
  hostName = config.networking.hostName;

  # Pick secrets for this host: global/ + machine/<host>/
  isForHost = name: let
    parts = lib.splitString "/" name;
    tier = builtins.elemAt parts 0;
    target = builtins.elemAt parts 1;
  in (tier == "global") || (tier == "machine" && target == hostName);

  hostSecrets = lib.filterAttrs (name: _: isForHost name) secretsData.configs;

  # Build age.secrets attrset
  toAgeSecret = name: config: {
    file = ./../../secrets/${name};
    inherit (config) mode owner;
  };

in {
  options.modules.secrets = {
    enable = lib.mkEnableOption "agenix secrets (NixOS)";
  };

  imports = [ agenix.nixosModules.default ];

  config = lib.mkIf cfg.enable {
    age = {
      identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_rsa_key"
      ];
      secrets = lib.mapAttrs toAgeSecret hostSecrets;
    };
  };
}
