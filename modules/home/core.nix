# Core home manager settings
{ config, pkgs, lib, ... }:

{
  home.username = "leoguy77";
  home.homeDirectory = "/home/leoguy77";
  home.stateVersion = "24.11";

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
    userName = "Leon";
    userEmail = "leonschneider29@googlemail.com";
    signing = {
      key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDAj4xwu7D5e0hN7+Tr46JZhvPGc/EehC7R22xAaHiypvU/620JZSakZID5+D6oIrG0z+my3BoweV+O3DpBoPvN9OOBlP05HsDf9AUY99io5wfWKkAKUZnXTHVoORwA/xp5DMHuPTS8cLKmqwBtAcEhL9+q4lVjDjZhagR69J7DycAC678YBZrH3g0yuciJBAaTIvZPDvlTeZHc3piKrlYRdjhFq6PJ8K7fi/RhtMOLDCFHV8kv71uV7+rD+isyPYhj3OAR2tyQxoBhxdqIQM7w+rPgm5km7rh58ErlWXC0ZsllPbLz/LVsoNPSq2GqnGGILb7vZE3ytD4lqEO1fhv4nXN7OlZPLO73Ti4b/RetqsmA0y6Yf58yLU+aTGTlZ6ytKd2gJx5/ne0jgoCV9fFaVnpxD0TBw0ME5jyABby9OlzpUm4Pheu/b3SSeH2/vYBLr/dAPLAd7ARz9ZP1BGm5BHjwWtsTrzsr3aRR+00o2VFLQcrwJyqGTwWzNvA0THfe5HS/+EZg142XgyI+nhm9vYI6rIXfnISYi4p+3TF0aUzAlWRy0LH/4UMCjQiCCEvBz9azPWecehUxCCfMAkIZQtc5MVcwz5kuNlgWYBBKF7aDCUHEG7GEG6Lm0U6eHfqkI48ajCCwvsMZmERuKtLr8vl9FbjucoGcp8Bp1XqXuw==";
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      merge.conflictstyle = "diff3";
      gpg.format = "ssh";
      "gpg \"ssh\"".program = "/run/current-system/sw/bin/op-ssh-sign";
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
  home.file.".ssh/Github.pub".text = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMeOpEP8l Github\n";
  
  # Create Github private key file (stub - actual key is in 1Password)
  home.file.".ssh/Github".text = "-----BEGIN OPENSSH PRIVATE KEY-----\n-----END OPENSSH PRIVATE KEY-----\n";

  # Shell aliases and functions
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "pip" "python" ];
      theme = "agnoster";
    };
    shellAliases = {
      ll = "eza -la --icons";
      ls = "eza";
      cat = "bat";
      grep = "rg";
    };
    initExtra = ''
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
    nix-direnv.enable = true;
  };

  programs.home-manager.enable = true;
}
