# Firmware blobs from the hardware enablement repos.
#
# Single purpose: install redistributable firmware (WiFi/BT/GPU blobs). On by
# default for physical machines; a KVM guest has none of that hardware and
# sets this false itself.
{
  config,
  lib,
  ...
}:

{
  options.modules.firmware = {
    enable = lib.mkEnableOption "redistributable hardware firmware";
  };

  config = lib.mkIf config.modules.firmware.enable {
    hardware.enableRedistributableFirmware = true;
  };
}
