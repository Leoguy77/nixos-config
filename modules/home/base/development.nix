# Development tools configuration
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.home.base.development;
in

{
  options.modules.home.base.development = {
    enable = lib.mkEnableOption "development home module";
    tmux = lib.mkEnableOption "tmux";
    mise = lib.mkEnableOption "mise version manager";
    onepassword = lib.mkEnableOption "1Password SSH agent";
  };

  config = lib.mkIf cfg.enable {
    # Tmux
    programs.tmux = lib.mkIf cfg.tmux {
      enable = true;
      prefix = "C-a";
      shell = "${pkgs.zsh}/bin/zsh";
      historyLimit = 10000;
      extraConfig = ''
        # Mouse support
        set -g mouse on
        
        # Vi mode
        setw -g mode-keys vi
        
        # Split panes
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        
        # Navigate panes with vim keys
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
        
        # Reload config
        bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      '';
    };

    # Mise (version manager)
    programs.mise = lib.mkIf cfg.mise {
      enable = true;
      settings = {
        legacy_version_file = true;
        trusted_config_paths = [ "~/projects" ];
      };
    };

    # 1Password SSH agent
    systemd.user.services.onepassword-ssh-agent = lib.mkIf cfg.onepassword {
      Unit = {
        Description = "1Password SSH Agent";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs._1password-cli}/bin/op-ssh-sign";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
