# Locale, timezone, keyboard, state version.
#
# Single purpose: the machine's locale/time/keyboard identity. Shared by
# desktops and servers. Fonts live in fonts.nix — a headless box should not
# carry a font stack in its closure.
{
  config,
  lib,
  myvars,
  ...
}:

{
  options.modules.locale = {
    enable = lib.mkEnableOption "locale, timezone and keyboard";

    germanSubLocales = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set the LC_* sub-locales (date format, currency, collation …) to
        de_DE.UTF-8 while LANG stays en_US.UTF-8. A desktop nicety for a
        German user; off by default so a server keeps a plain C/en_US locale.
      '';
    };
  };

  config = lib.mkIf config.modules.locale.enable {
    system.stateVersion = lib.mkDefault myvars.system.stateVersion;
    time.timeZone = lib.mkDefault myvars.system.timeZone;
    i18n.defaultLocale = lib.mkDefault myvars.system.defaultLocale;
    console.keyMap = lib.mkDefault myvars.system.keymap;

    # The console keymap above does NOT reach X11 or Wayland. Without this the
    # X server stays on its "us" default while the console is "de", which is
    # invisible in a Plasma Wayland session (KWin applies kxkbrc itself) but
    # wrong at SDDM, in xrdp sessions, and on a fresh install before KDE has
    # written its own keyboard config. Verified on kirito:
    #   /etc/X11/xorg.conf.d/00-keyboard.conf  Option "XkbLayout" "us"
    #   /etc/vconsole.conf                     KEYMAP=de
    services.xserver.xkb.layout = lib.mkDefault myvars.system.keymap;

    i18n.extraLocaleSettings = lib.mkIf config.modules.locale.germanSubLocales {
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
  };
}
