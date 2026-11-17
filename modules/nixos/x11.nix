# X11 display server.
{
  config,
  lib,
  ...
}:

{
  options.modules.x11 = {
    enable = lib.mkEnableOption "the X11 display server";
  };

  config = lib.mkIf config.modules.x11.enable {
    services.xserver.enable = true;
  };
}
