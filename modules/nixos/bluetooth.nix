# Bluetooth support (bluez daemon + the blueman tray applet).
#
# Single purpose: make Bluetooth radios usable. Distinct from networkmanager.nix
# — a machine can have WiFi and no Bluetooth, or Bluetooth and no WiFi.
#
# This does NOT drive any audio codec policy: WirePlumber picks up bluez
# devices on its own (nixos/modules/services/desktops/pipewire/wireplumber.nix
# asserts hsphfpd is off and ships its own 10-bluez.conf), so an A2DP headset
# works from this alone.
{
  config,
  lib,
  ...
}:

{
  options.modules.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth (bluez + blueman tray applet)";
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

    # The tray applet. `services.blueman` installs the package and its dbus
    # activation files; the applet itself is started per user by
    # services.blueman-applet in modules/home/gui/niri.nix, because daemons
    # belong to the system and session programs belong to the session.
    services.blueman.enable = true;
  };
}
