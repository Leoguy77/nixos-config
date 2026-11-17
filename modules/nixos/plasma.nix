# KDE Plasma desktop + SDDM.
{
  config,
  lib,
  ...
}:

{
  options.modules.plasma = {
    enable = lib.mkEnableOption "the KDE Plasma desktop with SDDM";
  };

  config = lib.mkIf config.modules.plasma.enable {
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };
}
