# TUI (Terminal UI) tools configuration
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.home.tui;
in

{
  options.modules.home.tui = {
    enable = lib.mkEnableOption "TUI tools module";
    btop = lib.mkEnableOption "btop system monitor";
    yazi = lib.mkEnableOption "yazi file manager";
    zellij = lib.mkEnableOption "zellij terminal multiplexer";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # System monitoring
      (lib.mkIf cfg.btop btop)
      
      # File management
      (lib.mkIf cfg.yazi yazi)
      
      # Terminal multiplexer (alternative to tmux)
      (lib.mkIf cfg.zellij zellij)
    ];

    # Btop configuration
    programs.btop = lib.mkIf cfg.btop {
      enable = true;
      settings = {
        color_theme = "catppuccin_mocha";
        theme_background = false;
        update_ms = 2000;
      };
    };

    # Yazi configuration
    programs.yazi = lib.mkIf cfg.yazi {
      enable = true;
      shellWrapperName = "y";  # New default (was "yy" in legacy)
      settings = {
        manager = {
          show_hidden = true;
          sort_by = "alphabetical";
        };
      };
    };
  };
}
