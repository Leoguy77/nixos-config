# Core home manager settings
{ config, pkgs, lib, ... }:

{
  home.username = "leoguy77";
  home.homeDirectory = "/home/leoguy77";
  home.stateVersion = "24.11";

  # Home Manager packages
  home.packages = with pkgs; [
    # CLI tools
    eza
    bat
    zoxide
    fzf
    
    # Development
    lazygit
    delta
    
    # Media
    mpv
    imagemagick
    
    # Password manager
    _1password-cli
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Leon";
    userEmail = "leonschneider29@googlemail.com";
    signing = {
      key = "BB6CEB57452F6236BA0001D7274249FAF8F3F735";
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      merge.conflictstyle = "diff3";
    };
  };

  # GPG configuration
  programs.gpg = {
    enable = true;
    settings = {
      keyserver = "keyserver.ubuntu.com";
    };
  };
  
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
  };

  # Shell aliases
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "pip" "python" ];
      theme = "agnoster";
    };
    shellAliases = {
      ll = "eza -la --icons";
      ls = "eza";
      cat = "bat";
      grep = "rg";
    };
  };

  # direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.home-manager.enable = true;
}
