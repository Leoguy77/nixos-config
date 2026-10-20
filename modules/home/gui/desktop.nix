# Desktop applications configuration
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.home.gui.desktop;
in

{
  options.modules.home.gui.desktop = {
    enable = lib.mkEnableOption "desktop home module";
    kitty = lib.mkEnableOption "kitty terminal";
    firefox = lib.mkEnableOption "firefox browser";
    spotify = lib.mkEnableOption "spotify music player";
    element = {
      enable = lib.mkEnableOption "element matrix client";

      settings = lib.mkOption {
        type = lib.types.submodule {
          options = {
            startInTray = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Start Element hidden in system tray";
            };
            minimizeToTray = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Minimize to tray instead of closing";
            };
            autoHideMenuBar = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Auto-hide the menu bar";
            };
            spellCheckerEnabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable spell checker";
            };
            openAtLoginMinimised = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Open Element at login, minimised to tray";
            };
            warnBeforeExit = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Warn before exiting Element";
            };
            locale = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "en" ];
              description = "Locale preferences";
            };
          };
        };
        default = { };
        description = "Element desktop settings";
      };
    };
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
      themeFile = lib.mkDefault "Catppuccin-Mocha";
    };

    # Firefox
    programs.firefox = lib.mkIf cfg.firefox {
      enable = true;
      configPath = lib.mkDefault "${config.xdg.configHome}/mozilla/firefox";
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

    # GUI applications
    home.packages = lib.mkMerge [
      (lib.mkIf cfg.spotify (with pkgs; [ spotify ]))
      (lib.mkIf cfg.element.enable (with pkgs; [ element-desktop ]))
      # wl-clipboard (wl-copy/wl-paste): Wayland clipboard CLI for terminals
      (lib.mkIf cfg.kitty [ pkgs.wl-clipboard ])
    ];

    # Element Matrix client
    xdg.configFile."Element/config.json" = lib.mkIf cfg.element.enable {
      text = builtins.toJSON {
        default_server_config = {
          "m.homeserver" = {
            base_url = "https://matrix-client.matrix.org";
            server_name = "matrix.org";
          };
          "m.identity_server" = {
            base_url = "https://vector.im";
          };
        };
        disable_custom_urls = false;
        disable_guests = true;
        disable_login_language_selector = false;
        disable_3pid_login = false;
        force_verification = false;
        brand = "Element";
        integrations_ui_url = "https://scalar.vector.im/";
        integrations_rest_url = "https://scalar.vector.im/api";
        integrations_widgets_urls = [
          "https://scalar.vector.im/_matrix/integrations/v1"
          "https://scalar.vector.im/api"
          "https://scalar-staging.vector.im/_matrix/integrations/v1"
          "https://scalar-staging.vector.im/api"
          "https://scalar-staging.riot.im/scalar/api"
        ];
        default_widget_container_height = 280;
        default_country_code = "GB";
        show_labs_settings = false;
        features = { };
        default_federate = true;
        default_theme = if cfg.darkMode then "dark" else "light";
        room_directory = {
          servers = [ "matrix.org" ];
        };
        enable_presence_by_hs_url = {
          "https://matrix.org" = false;
          "https://matrix-client.matrix.org" = false;
        };
        setting_defaults = {
          breadcrumbs = true;
        };
        jitsi = {
          preferred_domain = "meet.element.io";
        };
        element_call = {
          url = "https://call.element.io";
          participant_limit = 8;
          brand = "Element Call";
        };
        map_style_url = "https://api.maptiler.com/maps/streets/style.json?key=fU3vlMsMn4Jb6dnEIFsx";
      };
    };

    xdg.configFile."Element/electron-config.json" = lib.mkIf cfg.element.enable {
      text = builtins.toJSON {
        warnBeforeExit = cfg.element.settings.warnBeforeExit;
        minimizeToTray = cfg.element.settings.minimizeToTray;
        spellCheckerEnabled = cfg.element.settings.spellCheckerEnabled;
        autoHideMenuBar = cfg.element.settings.autoHideMenuBar;
        disableHardwareAcceleration = false;
        enableContentProtection = false;
        openAtLoginMinimised = cfg.element.settings.openAtLoginMinimised;
        safeStorageBackend = "kwallet6";
        locale = cfg.element.settings.locale;
      };
      # Don't override existing config (preserves safeStorage keys at runtime)
      # This writes initial defaults, subsequent runs update the file
    };

    # Dark mode preference
    dconf.settings = lib.mkIf cfg.darkMode {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };
}
