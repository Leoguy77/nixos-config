# Hyprland — a dynamic-tiling Wayland compositor.
#
# One of the mutually exclusive desktop choices in this directory. Use it
# together with profiles/desktop.nix, which carries everything that is NOT the
# desktop environment.
#
# X11 apps DO go through the X server here, unlike niri: Hyprland's module
# passes `enableXWayland = cfg.xwayland.enable` into wayland-session.nix
# (nixos/modules/programs/wayland/hyprland.nix:116), which sets
# `programs.xwayland.enable` — that is the Xwayland bundled with the X server.
# So the `xwayland.enable = true` below is load-bearing, not decoration.
_: {
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
