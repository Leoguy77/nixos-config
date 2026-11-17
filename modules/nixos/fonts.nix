# System fonts.
#
# Single purpose: which fonts exist system-wide. Split out of locale.nix so a
# headless server does not pull ~6 font packages and fontconfig into its
# closure just to get a timezone.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  options.modules.fonts = {
    enable = lib.mkEnableOption "system fonts";
  };

  config = lib.mkIf config.modules.fonts.enable {
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
  };
}
