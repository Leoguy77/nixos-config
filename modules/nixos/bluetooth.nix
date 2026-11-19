# Bluetooth support (bluez daemon).
#
# Single purpose: make Bluetooth radios usable. Distinct from networkmanager.nix
# — a machine can have WiFi and no Bluetooth, or Bluetooth and no WiFi.
#
# This does NOT drive any audio codec policy: WirePlumber picks up bluez
# devices on its own (nixos/modules/services/desktops/pipewire/wireplumber.nix
# asserts hsphfpd is off and ships its own 10-bluez.conf), so an A2DP headset
# works from this alone.
#
# There is deliberately NO tray applet. blueman used to be installed here for
# its applet; noctalia's bar has a bluetooth widget that opens a control-center
# section driving the same bluez API, and its binary registers
# org.bluez.Agent1 + AgentManager1 itself (verified by pairing and forgetting a
# device through it). blueman's applet would be a second icon for one radio.
{
  config,
  lib,
  ...
}:

{
  options.modules.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth (bluez daemon)";
  };

  config = lib.mkIf config.modules.bluetooth.enable {
    hardware.bluetooth = {
      enable = true;

      # Power the radio on at boot instead of leaving it soft-blocked until
      # something asks. Writes Policy.AutoEnable to /etc/bluetooth/main.conf.
      # Without it the adapter exists but reports "Powered: no" and a fresh
      # `bluetoothctl` session has to flip it by hand after every reboot.
      powerOnBoot = true;
    };
  };
}
