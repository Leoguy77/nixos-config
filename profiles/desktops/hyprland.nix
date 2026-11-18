# Hyprland — a dynamic-tiling Wayland compositor.
#
# One of the mutually exclusive desktop choices in this directory. Use it
# together with profiles/desktop.nix, which carries everything that is NOT the
# desktop environment.
#
# XWayland: `programs.hyprland.xwayland.enable` defaults to true, and the
# module's wayland-session.nix turns on `xwayland.enable` from it. That is what
# Steam and older X11 apps need, so nothing extra is required here — unlike
# niri.nix, which needs `services.xserver.enable` for it.
{ ... }:
{
  programs.hyprland = {
    enable = true;

    # Stated explicitly even though it is the default, so a later "cleanup" has
    # to argue with a comment instead of silently breaking X11 apps.
    xwayland.enable = true;
  };

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # The session name comes from the module's own `passthru.providedSessions`
  # (nixos/modules/programs/wayland/hyprland.nix:20). Pinned for the same
  # reason as in niri.nix: with several DE profiles in reach, a host that mixes
  # two should fail loudly instead of silently opening the wrong session.
  services.displayManager.defaultSession = "hyprland";
}
