# Home Manager overrides for this host. The shared base (shell, git, editor,
# terminal tools, desktop apps) is already imported by profiles/desktop.nix via
# modules/home/default.nix — this file only ADDS what is specific to this machine.
#
# The defaults it inherits: modules.home.core + base.development + tui + gui.desktop.
# Delete any line below that this host does not need.
{ ... }:

{
  modules.home.core.enable = true;
  modules.home.base.development.enable = true;
  modules.home.tui = {
    enable = true;
    btop = true;
    yazi = true;
  };
  modules.home.gui.desktop = {
    enable = true;
    kitty = true;
    firefox = true;
  };
}
