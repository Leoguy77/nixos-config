# PipeWire audio server (with ALSA/Pulse/JACK compatibility).
{
  config,
  lib,
  ...
}:

{
  options.modules.pipewire = {
    enable = lib.mkEnableOption "PipeWire audio";
  };

  config = lib.mkIf config.modules.pipewire.enable {
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };
}
