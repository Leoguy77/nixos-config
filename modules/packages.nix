# System packages
{ config, pkgs, lib, inputs, ... }:
let
  llm-agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Allow unfree packages
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password-gui"
    "1password-cli"
    "1password"
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
    
    # System monitoring
    htop
    btop
    neofetch
    
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
    
    # LLM tools
    llm-agents.pi
    
    # VSCode (FHS version for better compatibility)
    vscode.fhs
  ];
}
