# Development tools and environment
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Version manager
    mise
    
    # Terminal multiplexer
    tmux
  ];

  # Tmux configuration
  programs.tmux = {
    enable = true;
    clock24 = true;
    extraConfig = ''
      set -g mouse on
      set -g prefix C-a
      bind C-a send-prefix
    '';
  };

  # 1Password SSH Agent
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };

  # Add npm global bin to PATH
  home.sessionPath = [ "$HOME/.npm-global/bin" ];
}
