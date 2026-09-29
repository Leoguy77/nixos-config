# Core system settings
{ config, pkgs, lib, myvars, ... }:

let
  cfg = config.modules.system;
in

{
  options.modules.system = {
    enable = lib.mkEnableOption "system module";
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "surface";
      description = "The host name";
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = myvars.system.timeZone;
      description = "The time zone";
    };
    locale = lib.mkOption {
      type = lib.types.str;
      default = myvars.system.defaultLocale;
      description = "The default locale";
    };
    keymap = lib.mkOption {
      type = lib.types.str;
      default = myvars.system.keymap;
      description = "The console keymap";
    };
  };

  config = lib.mkIf cfg.enable {
    # System version
    system.stateVersion = lib.mkDefault myvars.system.stateVersion;

    # Nix settings
    nix = {
      settings = {
        experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
        # Disabled: with useGlobalPkgs + bundles, nix-store --optimise on every
        # boot (nix-optimise.service, wantedBy=multi-user.target) makes boot
        # take minutes on a large store. GC is still handled by nix.gc timer.
        auto-optimise-store = lib.mkDefault false;
        trusted-users = lib.mkForce [ "root" myvars.username ];
      };
      gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 14d";
      };
    };

    # Networking
    networking = {
      hostName = lib.mkDefault cfg.hostName;
      networkmanager.enable = lib.mkDefault true;
      firewall = {
        enable = lib.mkDefault true;
        allowedTCPPorts = lib.mkDefault [ 22 ]; # SSH
      };
    };

    # Time & Locale
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = cfg.locale;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = lib.mkDefault "de_DE.UTF-8";
      LC_IDENTIFICATION = lib.mkDefault "de_DE.UTF-8";
      LC_MEASUREMENT = lib.mkDefault "de_DE.UTF-8";
      LC_MONETARY = lib.mkDefault "de_DE.UTF-8";
      LC_NAME = lib.mkDefault "de_DE.UTF-8";
      LC_NUMERIC = lib.mkDefault "de_DE.UTF-8";
      LC_PAPER = lib.mkDefault "de_DE.UTF-8";
      LC_TELEPHONE = lib.mkDefault "de_DE.UTF-8";
      LC_TIME = lib.mkDefault "de_DE.UTF-8";
    };

    # Console keymap
    console.keyMap = cfg.keymap;

    # Fonts
    fonts = {
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
      ];
      fontconfig.defaultFonts = {
        monospace = lib.mkDefault [ "Fira Code" ];
        sansSerif = lib.mkDefault [ "Noto Sans" ];
        serif = lib.mkDefault [ "Noto Serif" ];
        emoji = lib.mkDefault [ "Noto Color Emoji" ];
      };
    };

    # Enable zsh for user shells
    programs.zsh.enable = lib.mkDefault true;
  };
}
