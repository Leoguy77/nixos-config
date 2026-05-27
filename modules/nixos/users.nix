# User configuration
{ config, pkgs, lib, ... }:

{
  users.users.leoguy77 = {
    isNormalUser = true;
    description = "Leon";
    extraGroups = [ "networkmanager" "wheel" "input" "video" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
      kitty
    ];
  };

  # Programs available to all users
  programs.zsh.enable = true;
  programs.git.enable = true;
  programs.direnv.enable = true;
  programs.less.enable = true;
}
