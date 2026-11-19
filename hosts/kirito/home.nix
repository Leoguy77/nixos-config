# Kirito-specific Home Manager configuration
# Replacement for Surface - full desktop/laptop with GUI support
{
  pkgs,
  myvars,
  inputs,
  ...
}:

{
  # Required by Home Manager
  home.stateVersion = myvars.system.stateVersion;

  # CLI + admin tools for this host
  home.packages = [
    pkgs.incus # Incus container CLI (client)
    pkgs.opentofu # OpenTofu — open-source Terraform (manages Incus VMs)
    pkgs.ausweisapp # German eID (nPA) reader — talks to the card via pcscd
    pkgs.gh # GitHub CLI (repo, PR, GPG/SSH key management)
  ];

  # Enable all home modules
  modules.home.core.enable = true;
  modules.home.base.development.enable = true;
  modules.home.tui.enable = true;
  modules.home.gui.desktop.enable = true;
  modules.home.gui.pi.enable = true;

  # Niri session: compositor config, noctalia bar, fuzzel, hyprlock.
  modules.home.desktops.niri.enable = true;

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

  # Home-manager sops disabled: pi's MCP config is now a system-level
  # sops secret (declared in hosts/kirito/default.nix) decrypted with
  # kirito's age host key — headless, no card needed. The GPG-card route was
  # tried and rejected: the sops-nix user unit runs headless (no TTY for
  # pinentry), so every rebuild/reboot depended on the agent's PIN cache.
  # modules.home.sops.enable = true;
}
