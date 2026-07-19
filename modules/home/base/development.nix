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
      globalConfig.settings = {
        legacy_version_file = true;
        trusted_config_paths = [ "~/projects" ];
      };
    };

    # The 1Password SSH agent socket (~/.1password/agent.sock) is
    # provided by the 1Password desktop app (autostarted below).
    # op-ssh-sign is only used for git commit signing, not as a daemon.
    # It's configured in programs.git.gpg.ssh.program in core.nix.

    # Export SSH_AUTH_SOCK so CLI tools (ssh, ssh-add, git signing hooks)
    # discover the 1Password agent. Without this only programs.ssh's
    # IdentityAgent setting applies, leaving SSH_AUTH_SOCK unset in shells.
    home.sessionVariables = lib.mkIf cfg.onepassword {
      SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    };

    # 1Password GUI autostart
    systemd.user.services.onepassword = lib.mkIf cfg.onepassword {
      Unit = {
        Description = "1Password";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
