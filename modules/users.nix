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
    ];
  };

  # Zsh as default shell
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Better terminal
  programs.kitty = {
    enable = true;
    font = {
      name = "Fira Code";
      size = 12;
    };
    settings = {
      confirm_os_window_close = "0";
      enable_audio_bell = "no";
    };
  };

  # Git configuration
  programs.git = {
    enable = true;
    lfs.enable = true;
  };

  # direnv for project environments
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Less with better keybindings
  programs.less = {
    enable = true;
    keys = {
      home = "beginning-of-line";
      end = "end-of-line";
    };
  };
}
