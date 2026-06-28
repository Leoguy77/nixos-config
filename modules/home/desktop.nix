# Desktop environment and UI settings
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Browser
    firefox
    # Matrix client
    element-desktop
  ];

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

  # Dark mode preference
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
