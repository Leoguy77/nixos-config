# Home Manager configuration
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
    tmux
    
    # Development
    lazygit
    delta
    
    # Media
    mpv
    imagemagick
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
    publicKeys = [{
      source = "/home/leoguy77/.gnupg/public-keys.d";
      trust = 5;
    }];
  };

  # Zsh configuration
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

  # Kitty terminal
  programs.kitty = {
    enable = true;
    font = {
      name = "Fira Code";
      size = 12;
    };
    settings = {
      confirm_os_window_close = "0";
      enable_audio_bell = "no";
      window_padding_width = "10";
    };
    theme = "Catppuccin-Mocha";
  };

  # direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Tmux
  programs.tmux = {
    enable = true;
    clock24 = true;
    extraConfig = ''
      set -g mouse on
      set -g prefix C-a
      bind C-a send-prefix
    '';
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # Dconf for GTK/Qt settings
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
