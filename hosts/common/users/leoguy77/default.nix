{
  pkgs,
  config,
  lib,
  ...
}: let
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in {
  users.mutableUsers = false;
  users.users.leoguy77 = {
    isNormalUser = true;
    shell = pkgs.bash;
    extraGroups = ifTheyExist [
      "audio"
      "docker"
      "git"
      "i2c"
      "libvirtd"
      "mysql"
      "network"
      "plugdev"
      "podman"
      "video"
      "wheel"
      "wireshark"
    ];

    openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../../../home/leoguy77/ssh.pub);
    hashedPasswordFile = config.sops.secrets.leoguy77-password.path;
    packages = [pkgs.home-manager];
  };

  sops.secrets.leoguy77-password = {
    sopsFile = ../../secrets.yaml;
    neededForUsers = true;
  };

  home-manager.users.leoguy77 = import ../../../../home/leoguy77/${config.networking.hostName}.nix;

  security.pam.services = {
    swaylock = {};
  };
}
