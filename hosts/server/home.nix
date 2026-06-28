# Server-specific Home Manager configuration
# TUI-only configuration for headless servers
{ config, pkgs, lib, myvars, ... }:

{
  # Enable only base and TUI modules (NO GUI)
  modules.home.core.enable = true;
  modules.home.base.development.enable = true;
  modules.home.tui.tools.enable = true;
  # modules.home.gui.desktop.enable = false  # No GUI on headless servers
  # modules.home.gui.pi.enable = false
  
  # TUI tools for server management
  modules.home.tui.tools.btop = true;
  modules.home.tui.tools.yazi = false;  # Optional on servers
  
  # Development tools
  modules.home.base.development.tmux = true;
  modules.home.base.development.mise = true;
  modules.home.base.development.onepassword = true;
  
  # Server-specific overrides - disable GUI programs
  programs.kitty.enable = lib.mkForce false;
  programs.firefox.enable = lib.mkForce false;
}
