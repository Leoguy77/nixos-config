# Home Manager agenix secrets — wires user/ + shared/<host>/ tiers
{ config, pkgs, lib, agenix, myvars, ... }:

let
  cfg = config.modules.home.secrets;
  secretsData = import ../../secrets/secrets.nix { inherit myvars; };

  # Pick secrets for this host: user/ + shared/<host>/
  isForHost = name: let
    parts = lib.splitString "/" name;
    tier = builtins.elemAt parts 0;
    target = builtins.elemAt parts 1;
  in (tier == "user") || (tier == "shared" && target == config.networking.hostName);

  userSecrets = lib.filterAttrs (name: _: isForHost name) secretsData.configs;

  toAgeSecret = name: config: {
    file = ../../secrets/${name};
    inherit (config) mode owner;
  };

in {
  options.modules.home.secrets = {
    enable = lib.mkEnableOption "agenix secrets (home-manager)";
  };

  imports = [ agenix.homeManagerModules.default ];

  config = lib.mkIf cfg.enable {
    age = {
      identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"   # fallback to host key
        "${config.home.homeDirectory}/.ssh/id_ed25519"  # user's own key
        "${config.home.homeDirectory}/.ssh/id_rsa"
      ];
      secrets = lib.mapAttrs toAgeSecret userSecrets;
    };
  };
}
