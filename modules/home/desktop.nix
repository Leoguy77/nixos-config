# Desktop applications configuration
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.home.desktop;
in

{
  options.modules.home.desktop = {
    enable = lib.mkEnableOption "desktop home module";
    kitty = lib.mkEnableOption "kitty terminal";
    firefox = lib.mkEnableOption "firefox browser";
    darkMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable dark mode preference";
    };
  };

  config = lib.mkIf cfg.enable {
    # Kitty terminal
    programs.kitty = lib.mkIf cfg.kitty {
      enable = true;
      font = {
        name = "Fira Code";
        size = lib.mkDefault 12;
      };
      settings = {
        confirm_os_window_close = lib.mkDefault 0;
        enable_audio_bell = lib.mkDefault false;
        window_padding_width = lib.mkDefault 10;
      };
      theme = lib.mkDefault "Catppuccin-Mocha";
    };

    # Firefox
    programs.firefox = lib.mkIf cfg.firefox {
      enable = true;
      profiles.default = {
        id = 0;
        name = "default";
        isDefault = true;
        settings = {
          "font.name.monospace.x-western" = "Fira Code";
          "browser.theme.content-theme" = lib.mkIf cfg.darkMode 0;
          "browser.theme.toolbar-theme" = lib.mkIf cfg.darkMode 0;
        };
      };
    };

    # Dark mode preference
    dconf.settings = lib.mkIf cfg.darkMode {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };
}
