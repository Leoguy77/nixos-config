# Home Manager modules
# Organized into: base (shared), tui (terminal), gui (desktop)
{ ... }:

{
  imports = [
    # Base modules (shared everywhere)
    ./base/core.nix
    ./base/development.nix

    # TUI tools (terminal UI)
    ./tui/tools.nix

    # sops (sops-nix) secrets
    # (home-manager sops module removed — pi_mcp_json moved to system-level
    # decryption in hosts/kirito/default.nix, see below)

    # GUI applications (desktop/laptop)
    ./gui/desktop.nix
    ./gui/pi.nix

    # Wayland sessions. Each stays inert until its host sets
    # modules.home.desktops.<name>.enable = true.
    ./gui/niri.nix
  ];
}
