# Niri — a scrollable-tiling Wayland compositor.
#
# One of the mutually exclusive desktop choices in this directory. Use it
# together with profiles/desktop.nix, which carries everything that is NOT the
# desktop environment.
#
# Wayland-only, but `services.xserver.enable` is still turned on: that is what
# ships XWayland, and without it Steam and older X11 apps do not start. The cost
# is a small closure; the cost of dropping it is a machine that cannot run them.
{ config, ... }:
{
  programs.niri.enable = true;

  # XWayland for Steam / legacy X11 apps. NOT `modules.x11` — that would also
  # pull in the X11 session machinery and a display manager X session Niri has
  # no use for.
  services.xserver.enable = true;

  # Display manager. SDDM is already in the repo and can start a Wayland
  # session; GNOME's GDM would drag in a second desktop stack.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # Niri's own module defaults this to "niri" for GDM's sake; with SDDM the
  # session list is explicit, so pin it rather than relying on that default.
  services.displayManager.defaultSession = "niri";

  assertions = [
    {
      assertion = config.programs.niri.enable;
      message = "profiles/desktops/niri.nix expects programs.niri; the NixOS module is missing from the pin.";
    }
  ];
}
