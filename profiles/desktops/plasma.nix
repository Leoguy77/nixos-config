# KDE Plasma 6 on X11 + SDDM.
#
# One of the mutually exclusive desktop choices in this directory: a host
# imports exactly one file from here, in addition to profiles/desktop.nix (which
# carries everything that is NOT the desktop environment — audio, fonts, users,
# backup, ...).
#
# Explicit rather than implied: `services.xserver.enable = true` is what
# provides XWayland under Plasma Wayland AND the X11 session that
# `startplasma-x11` (used by modules.rdp) needs. Dropping it saves a little
# closure but silently breaks RDP, so it belongs in the file that names the DE.
{ config, ... }:
{
  modules.x11.enable = true;
  modules.plasma.enable = true;

  # Plasma is a per-host opt-in that expects a graphical session; SDDM is its
  # greeter and is enabled by modules.plasma itself, so nothing else is needed.
  assertions = [
    {
      assertion = !config.modules.rdp.enable || config.services.xserver.enable;
      message = ''
        modules.rdp uses `startplasma-x11`, which needs services.xserver.enable
        (set by profiles/desktops/plasma.nix). Enable that profile or drop RDP.
      '';
    }
  ];
}
