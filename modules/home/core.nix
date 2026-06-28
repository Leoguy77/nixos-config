# Core home manager settings
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.home.core;
in

{
  options.modules.home.core = {
    enable = lib.mkEnableOption "core home module";
    username = lib.mkOption {
      type = lib.types.str;
      default = "leoguy77";
      description = "Home manager username";
    };
    gitUserName = lib.mkOption {
      type = lib.types.str;
      default = "Leon";
      description = "Git user name";
    };
    gitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = "leonschneider29@googlemail.com";
      description = "Git user email";
    };
  };

  config = lib.mkIf cfg.enable {
    home.username = cfg.username;
    home.homeDirectory = lib.mkDefault "/home/${cfg.username}";
    home.stateVersion = lib.mkDefault "24.11";

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
      
      # Password manager
      _1password-cli
    ];

    # Git configuration
    programs.git = {
      enable = true;
      userName = cfg.gitUserName;
      userEmail = cfg.gitUserEmail;
      signing = {
        key = lib.mkDefault "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDAj4xwu7D5e0hN7+Tr46JZhvPGc/EehC7R22xAaHiypvU/620JZSakZID5+D6oIrG0z+my3BoweV+O3DpBoPvN9OOBlP05HsDf9AUY99io5wfWKkAKUZnXTHVoORwA/xp5DMHuPTS8cLKmqwBtAcEhL9+q4lVjDjZhagR69J7DycAC678YBZrH3g0yuciJBAaTIvZPDvlTeZHc3piKrlYRdjhFq6PJ8K7fi/RhtMOLDCFHV8kv71uV7+rD+isyPYhj3OAR2tyQxoBhxdqIQM7w+rPgm5km7rh58ErlWXC0ZsllPbLz/LVsoNPSq2GqnGGILb7vZE3ytD4lqEO1fhv4nXN7OlZPLO73Ti4b/RetqsmA0y6Yf58yLU+aTGTlZ6ytKd2gJx5/ne0jgoCV9fFaVnpxD0TBw0ME5jyABby9OlzpUm4Pheu/b3SSeH2/vYBLr/dAPLAd7ARz9ZP1BGm5BHjwWtsTrzsr3aRR+00o2VFLQcrwJyqGTwWzNvA0THfe5HS/+EZg142XgyI+nhm9vYI6rIXfnISYi4p+3TF0aUzAlWRy0LH/4UMCjQiCCEvBz9azPWecehUxCCfMAkIZQtc5MVcwz5kuNlgWYBBKF7aDCUHEG7GEG6Lm0U6eHfqkI48ajCCwvsMZmERuKtLr8vl9FbjucoGcp8Bp1XqXuw==";
        signByDefault = lib.mkDefault true;
      };
      extraConfig = {
        init.defaultBranch = lib.mkDefault "main";
        pull.rebase = lib.mkDefault true;
        merge.conflictstyle = lib.mkDefault "diff3";
        gpg.format = lib.mkDefault "ssh";
        "gpg \"ssh\"".program = lib.mkDefault "/run/current-system/sw/bin/op-ssh-sign";
      };
    };

    # SSH configuration for GitHub to use the Github key from 1Password SSH agent
    programs.ssh = {
      enable = true;
      extraConfig = ''
        Host github.com
          HostName github.com
          User git
          IdentityFile ~/.ssh/Github
          IdentitiesOnly yes
          IdentityAgent ~/.1password/agent.sock
      '';
    };

    # Create Github public key file
    home.file.".ssh/Github.pub".text = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMEOpEP8l Github\n";
    
    # Create Github private key file (stub - actual key is in 1Password)
    home.file.".ssh/Github".text = lib.mkDefault "-----BEGIN OPENSSH PRIVATE KEY-----\n-----END OPENSSH PRIVATE KEY-----\n";

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
      initExtra = lib.mkDefault ''
        # Smart home light control
        function space {
            if [ "$1" = "off" ]; then
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_3/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sitzecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sitzecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/trinkregal/n_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/trinkregal/n_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/spind/set" -m "{\"state\": \"OFF\"}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/3ddruck/wand/set" -m "{\"state\": \"OFF\"}"
            else
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sofaecke/decke_3/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sitzecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/sitzecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/trinkregal/n_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/trinkregal/n_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/spind/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/3ddruck/wand/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            fi
        }

        function space_elektro {
            mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
            mosquitto_pub -h 192.168.3.145 -t "zigbee2mqtt/elektro_ecke/decke_3/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
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
