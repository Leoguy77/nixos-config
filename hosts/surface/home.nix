# Surface-specific Home Manager configuration
# This is a desktop/laptop with full GUI support
{ config, pkgs, lib, myvars, pkgs-stable, inputs, ... }:

{
  # Required by Home Manager
  home.stateVersion = myvars.system.stateVersion;
  
  # Enable all home modules
  modules.home.core.enable = true;
  modules.home.base.development.enable = true;
  modules.home.tui.enable = true;
  modules.home.gui.desktop.enable = true;
  modules.home.gui.pi.enable = true;
  
  # TUI tools
  modules.home.tui.btop = true;
  modules.home.tui.yazi = true;
  
  # GUI apps
  modules.home.gui.desktop.kitty = true;
  modules.home.gui.desktop.firefox = true;
  modules.home.gui.desktop.spotify = true;
  modules.home.gui.desktop.element = {
    enable = true;
    settings = {
      startInTray = true;
      minimizeToTray = true;
      autoHideMenuBar = true;
      spellCheckerEnabled = true;
      openAtLoginMinimised = true;
      warnBeforeExit = true;
    };
  };
  modules.home.gui.desktop.darkMode = true;
  
  # Development tools
  modules.home.base.development.tmux = true;
  modules.home.base.development.mise = true;
  modules.home.base.development.onepassword = true;
  
  # Pass LLM agents package to pi module
  modules.home.gui.pi.llmAgentsPackage = inputs.llm-agents.packages.${pkgs.system}.pi;
  
  # Pi extensions
  modules.home.gui.pi.extensions = true;
  
  # Surface-specific overrides can go here
  # Example: different git config for work vs personal
  # programs.git.extraConfig.user.name = "Leon (Surface)";
  
  # Enable caffeine-ng service for system tray
  services.caffeine.enable = true;
}
