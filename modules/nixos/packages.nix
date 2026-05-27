# System packages
{ config, pkgs, lib, inputs, ... }:
let
  llm-agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Allow unfree packages
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password"
    "1password-gui"
    "1password-cli"
    "code"
    "vscode"
  ];

  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    curl
    wget
    vim
    nano
    home-manager
    
    # System monitoring
    htop
    btop
    fastfetch
    
    # File utilities
    ripgrep
    fd
    jq
    tree
    file
    
    # Development
    python3
    nodejs
    gcc
    gnumake
    cmake
    
    # Network
    networkmanagerapplet
    inetutils
    
    # Security
    gnupg
    age
    
    # Password manager
    _1password-gui
    
    # LLM tools
    llm-agents.pi
    
    # VSCode (FHS version for better compatibility)
    vscode.fhs
  ];
}
