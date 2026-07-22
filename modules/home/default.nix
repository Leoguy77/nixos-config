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
    
    # Agenix user secrets
    ./secrets.nix
    
    # GUI applications (desktop/laptop)
    ./gui/desktop.nix
    ./gui/pi.nix
  ];
}
