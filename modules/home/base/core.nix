# Core home manager settings
{ config, pkgs, lib, myvars, ... }:

let
  cfg = config.modules.home.core;
in

{
  options.modules.home.core = {
    enable = lib.mkEnableOption "core home module";
    username = lib.mkOption {
      type = lib.types.str;
      default = myvars.username;
      description = "Home manager username";
    };
    gitUserName = lib.mkOption {
      type = lib.types.str;
      default = myvars.git.userName;
      description = "Git user name";
    };
    gitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = myvars.git.userEmail;
      description = "Git user email";
    };
  };

  config = lib.mkIf cfg.enable {
    home.username = cfg.username;
    home.homeDirectory = lib.mkDefault "/home/${cfg.username}";
    home.stateVersion = lib.mkDefault myvars.system.stateVersion;

    # Home Manager packages
    home.packages = with pkgs; [
      # CLI tools
      eza
      bat
      zoxide
      fzf
      
      # Development
      lazygit
      delta
      
      # Media
      mpv
      imagemagick
      
      # Password manager: provided system-wide via programs._1password*
      # (modules.onepassword) so the desktop-app CLI integration works.
      
      # Smart home (MQTT client)
      mosquitto
    ];

    # Git configuration
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = cfg.gitUserName;
          email = cfg.gitUserEmail;
        };
        init.defaultBranch = lib.mkDefault "main";
        pull.rebase = lib.mkDefault true;
        merge.conflictstyle = lib.mkDefault "diff3";
        gpg = {
          format = lib.mkDefault "ssh";
          "ssh".program = lib.mkDefault "/run/current-system/sw/bin/op-ssh-sign";
        };
      };
      signing = {
        key = lib.mkDefault myvars.git.signingKey;
        signByDefault = lib.mkDefault true;
      };
    };

    # SSH configuration: use 1Password SSH agent for all connections
    programs.ssh = {
      enable = true;
      # enableDefaultConfig must be false when manually setting defaults via settings."*"
      enableDefaultConfig = false;
      settings = {
        # Defaults for all hosts
        "*" = {
          AddKeysToAgent = "no";
          Compression = "no";
          ControlMaster = "no";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "no";
          ForwardAgent = "no";
          HashKnownHosts = "no";
          ServerAliveCountMax = 3;
          ServerAliveInterval = 0;
          UserKnownHostsFile = "~/.ssh/known_hosts";
          IdentityAgent = "~/.1password/agent.sock";
        };
        # GitHub specifics
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/Github";
          IdentitiesOnly = "yes";
          IdentityAgent = "~/.1password/agent.sock";
        };
      };
    };

    # Create Github public key file
    home.file.".ssh/Github.pub" = {
      text = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMeOpEP8l Github\n";
      force = true;  # Overwrite existing file
    };
    
    # Create Github private key file (stub - actual key is in 1Password)
    home.file.".ssh/Github" = {
      text = lib.mkDefault "-----BEGIN OPENSSH PRIVATE KEY-----\n-----END OPENSSH PRIVATE KEY-----\n";
      force = true;  # Overwrite existing file
    };

    # SUDO_ASKPASS — GUI password dialog for pi agent's sudo calls
    home.sessionVariables.SUDO_ASKPASS = "${config.home.homeDirectory}/.config/askpass";

    # Deploy askpass helper to a stable path
    home.file.".config/askpass" = {
      source = ./../../../askpass.sh;
      executable = true;
    };

    # Shell aliases and functions
    programs.zsh = {
      enable = true;
      autosuggestion.enable = lib.mkDefault true;
      syntaxHighlighting.enable = lib.mkDefault true;
      oh-my-zsh = {
        enable = true;
        plugins = lib.mkDefault [ "git" "docker" "pip" "python" ];
        theme = lib.mkDefault "agnoster";
      };
      shellAliases = {
        ll = lib.mkDefault "eza -la --icons";
        ls = lib.mkDefault "eza";
        cat = lib.mkDefault "bat";
        grep = lib.mkDefault "rg";
      };
      initContent = lib.mkForce ''
        # oh-my-zsh configuration
        plugins=(git docker pip python)
        ZSH_THEME="agnoster"
        source $ZSH/oh-my-zsh.sh
        
        # History options
        HISTSIZE=10000
        SAVEHIST=10000
        HISTFILE=~/.zsh_history
        setopt HIST_FCNTL_LOCK HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY
        
        # Smart home light control
        function space {
            if [ "$1" = "off" ]; then
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_3/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sitzecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sitzecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/trinkregal/n_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/trinkregal/n_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/spind/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/3ddruck/wand/set" -m "{\"state\": \"OFF\"}"
            else
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sofaecke/decke_3/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sitzecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/sitzecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/trinkregal/n_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/trinkregal/n_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/spind/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/3ddruck/wand/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            fi
        }

        function space_elektro {
            mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            mosquitto_pub -h ${myvars.networking.smartHome.mqttBroker} -t "zigbee2mqtt/elektro_ecke/decke_3/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
        }
        
        # Aliases
        alias ll='eza -la --icons'
        alias ls=eza
        alias cat=bat
        alias grep=rg
        
        # Yazi directory change function
        function y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
          command yazi "$@" --cwd-file="$tmp"
          if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
            builtin cd -- "$cwd"
          fi
          rm -f -- "$tmp"
        }
      '';
    };

    # direnv
    programs.direnv = {
      enable = true;
      nix-direnv.enable = lib.mkDefault true;
    };

    programs.home-manager.enable = lib.mkDefault true;
  };
}
