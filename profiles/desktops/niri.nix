# Niri — a scrollable-tiling Wayland compositor.
#
# One of the mutually exclusive desktop choices in this directory. Use it
# together with profiles/desktop.nix, which carries everything that is NOT the
# desktop environment.
#
# X11 apps go through `xwayland-satellite`, NOT through an X server. niri's NixOS
# module calls wayland-session.nix with `enableXWayland = false` (found at
# nixos/modules/programs/wayland/niri.nix:85) and instead speaks the X11 socket
# itself, exec'ing `xwayland-satellite` on demand
# (src/utils/xwayland/satellite.rs:99-115). `services.xserver.enable` does NOT
# provide that — the two are unrelated, and turning the X server on here would
# add a whole X session stack that never gets used.
#
# So `services.xserver.enable` is NOT set here. The one thing that used to
# force it was SDDM: without Wayland it asserts on the X server
# (nixos/modules/services/display-managers/sddm.nix:350, `xcfg.enable ||
# cfg.wayland.enable`). `sddm.wayland.enable` below satisfies that same
# assertion, so the machine still logs in with no X server installed.
{ pkgs, ... }:
{
  programs.niri.enable = true;

  # File manager. niri has no desktop shell and ships no file browser, so this
  # is the one graphical file manager on the box. The NixOS module (rather than
  # a bare home.packages entry) is what wires up the dbus-activated services:
  # thunar's daemon (single-instance, bulk rename), xfconf for its settings, and
  # the systemd user units it ships.
  programs.thunar.enable = true;

  # Right-click extract/create archive, and correct handling of removable media
  # (eject buttons, mount policies) instead of leaving it to gvfs' defaults.
  programs.thunar.plugins = with pkgs; [
    thunar-archive-plugin
    thunar-volman
  ];

  # Thunar itself only lists directories. gvfs is what backs trash://, sftp://,
  # smb:// and mtp:// (phones) — and it pulls in the udisks2 mounting rules
  # that make removable media appear at all. Without it a plugged-in USB stick
  # silently never shows up.
  services.gvfs.enable = true;

  # Without a thumbnailer Thunar draws a generic icon for every image and video;
  # ~/.cache/thumbnails did not exist before this. tumbler is the Xfce dbus
  # service that produces them.
  services.tumbler.enable = true;

  # Puts `xwayland-satellite` on PATH. niri looks it up by bare name
  # (niri-config/src/lib.rs:1707 `path: "xwayland-satellite"`), so without this
  # package X11 apps silently do nothing — niri logs "disabling integration".
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  # Display manager. SDDM is already in the repo and can start a Wayland
  # session; GDM would drag in a second desktop stack.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # niri's own module sets this to "niri" with mkDefault; pinned for the same
  # reason as in plasma.nix and hyprland.nix — with several DE profiles in
  # reach, a host that mixes two should fail loudly instead of silently
  # opening the wrong session.
  services.displayManager.defaultSession = "niri";
}
