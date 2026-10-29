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
    ./sops.nix
    
    # GUI applications (desktop/laptop)
    ./gui/desktop.nix
    ./gui/pi.nix
  ];
}
