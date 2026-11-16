# Core home manager settings
{
  config,
  pkgs,
  lib,
  myvars,
  ...
}:

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
      uv # provides uvx — Python tool runner for MCP servers (e.g. mcp-nixos)
      python3 # base interpreter uv/uvx and pip tools use

      # Media
      mpv
      imagemagick

      # KDE askpass dialog for GUI sudo (used by SUDO_ASKPASS / .config/askpass
      # so the pi agent can prompt for the password via a Plasma dialog)
      kdePackages.kdialog

      # Password manager: provided system-wide via programs._1password*
      # (modules.onepassword) so the desktop-app CLI integration works.

      # Smart home (MQTT client)
      mosquitto
    ];

    # GnuPG: card-backed OpenPGP (Token2), managed declaratively so a fresh
    # machine works without the hand-written ~/.gnupg files.
    programs.gpg = {
      enable = true;
      # scdaemon's internal CCID driver does not work with the Token2 reader;
      # the pcscd daemon (services.pcscd) must drive it instead.
      scdaemonSettings.disable-ccid = true;
    };

    services.gpg-agent = {
      enable = true;
      # Expose the A subkey over the agent's SSH socket. This also exports
      # SSH_AUTH_SOCK in the shell, pointing gpg-agent.
      enableSshSupport = true;
      # The auth subkey's keygrip (OPENPGP.3). Both cards carry the same key,
      # so this one entry covers either token and any replacement card.
      sshKeys = [ "0BF868B83537230B562981D7D864804892670786" ];
      # GUI prompt: the agent must be able to ask for the card PIN from
      # contexts with no terminal (git hooks, editors, this agent's shell).
      pinentry.package = pkgs.pinentry-qt;
      # PIN cache for SSH signatures. 7.5 minutes is short enough that a
      # walked-away-from session stops signing quickly, long enough to finish a
      # git push without retyping. Touch is still required on every signature —
      # UIF Auth=on is on the card, not negotiable from here.
      defaultCacheTtlSsh = 450;
      # gpg's own ceiling is 2 h; halved to 1 h so the window can't be slid
      # indefinitely by keeping the session busy.
      maxCacheTtlSsh = 3600;
    };

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
          # OpenPGP signing via the Token2 card's S subkey (gpg-agent handles
          # card selection, PIN and touch). The old ssh/op-ssh-sign route
          # through 1Password is retired.
          format = lib.mkDefault "openpgp";
        };
      };
      signing = {
        key = lib.mkDefault myvars.git.signingKey;
        signByDefault = lib.mkDefault true;
      };
    };

    # SSH configuration: Token2 hardware keys (ed25519-sk, resident +
    # verify-required) primary, 1Password agent as fallback for hosts where
    # they are not yet enrolled.
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
          # One credential for every host: the OpenPGP auth subkey
          # 11BE08BBC020EF46, served by gpg-agent's SSH socket. Both tokens and
          # any replacement card carry the same subkey, so hosts get ONE public
          # key that never needs re-adding. PIN unlocks it; touch signs.
          #
          # The braces are required: ssh expands ${XDG_RUNTIME_DIR} here, but a
          # bare $VAR/... is rejected as an invalid environment name.
          IdentityAgent = "\${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh";
          # IdentityFile = none is load-bearing: ssh otherwise falls back to its
          # built-in defaults (~/.ssh/id_ed25519, id_rsa, ...) and offers those
          # before the card — offering a stale key first gets you rejected or,
          # worse, authenticated with the wrong key. Verified: without it ssh
          # offers id_ed25519; with it, only the card's key.
          IdentityFile = "none";
          # IdentitiesOnly must stay NO: it means "only use IdentityFile keys",
          # and the key we want comes from the agent, not a file. Verified —
          # with "yes", nothing is offered at all.
          IdentitiesOnly = "no";
        };
        # GitHub specifics — same single key, but git needs the explicit user.
        "github.com" = {
          HostName = "github.com";
          User = "git";
        };
      };
    };

    # SUDO_ASKPASS — GUI password dialog for pi agent's sudo calls
    home.sessionVariables.SUDO_ASKPASS = "${config.home.homeDirectory}/.config/askpass";

    # uv/uvx must use the Nix system Python, not download a generic glibc build
    # that NixOS can't run (see nix.dev stub-ld). Global so every uv-based MCP
    # server (uvx mcp-nixos, etc.) works.
    home.sessionVariables.UV_PYTHON_DOWNLOADS = "never";

    # Deploy askpass helper to a stable path (lives with the sudo-askpass pi
    # extension under pi-extensions/sudo-askpass/). Generated here so it embeds
    # kdialog's ABSOLUTE store path — the helper must work even when the agent's
    # bash PATH does not include the home-manager bin (which is where kdialog
    # lives). kdialog is also declared in home.packages above.
    home.file.".config/askpass" = {
      text = ''
        #!/usr/bin/env bash
        # GUI askpass helper for KDE Plasma — pops up a password dialog.
        # Used by SUDO_ASKPASS for non-terminal sudo (e.g. pi agent).
        # Uses kdialog's absolute store path so it works regardless of PATH.
        exec ${lib.getExe pkgs.kdePackages.kdialog} --title "sudo" --password "Password for sudo:"
      '';
      executable = true;
    };

    # Shell aliases and functions
    programs.zsh = {
      enable = true;
      autosuggestion.enable = lib.mkDefault true;
      syntaxHighlighting.enable = lib.mkDefault true;
      oh-my-zsh = {
        enable = true;
        plugins = lib.mkDefault [
          "git"
          "docker"
          "pip"
          "python"
        ];
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

        # gpg-agent pinentry needs to know the controlling terminal
        export GPG_TTY=$(tty)
        # The agent is socket-activated by systemd, so it did not inherit
        # DISPLAY from a login shell — tell it the current one or pinentry-qt
        # fails with "cannot open display".
        gpg-connect-agent --quiet updatestartuptty /bye >/dev/null 2>&1

        # History options
        HISTSIZE=10000
        SAVEHIST=10000
        HISTFILE=~/.zsh_history
        setopt HIST_FCNTL_LOCK HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

        # Smart home light control
        function space {
            local mqtt_host=${myvars.networking.smartHome.mqttBroker}

            if [ "$1" = "off" ]; then
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_1/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_2/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_3/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sitzecke/decke_1/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sitzecke/decke_2/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/trinkregal/n_1/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/trinkregal/n_2/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/spind/set" -m '{"state": "OFF"}'
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/3ddruck/wand/set" -m '{"state": "OFF"}'
            elif [ -z "$1" ]; then
                # Show current state and brightness of all space lights
                local topics=(
                    "zigbee2mqtt/sofaecke/decke_1"
                    "zigbee2mqtt/sofaecke/decke_2"
                    "zigbee2mqtt/sofaecke/decke_3"
                    "zigbee2mqtt/sitzecke/decke_1"
                    "zigbee2mqtt/sitzecke/decke_2"
                    "zigbee2mqtt/trinkregal/n_1"
                    "zigbee2mqtt/trinkregal/n_2"
                    "zigbee2mqtt/elektro_ecke/decke_1"
                    "zigbee2mqtt/elektro_ecke/decke_2"
                    "zigbee2mqtt/spind"
                    "zigbee2mqtt/3ddruck/wand"
                )

                echo "space light states:"
                local result=$(mosquitto_sub -h "$mqtt_host" -F '%t %p' -C 11 -W 2 ''${topics[@]/#/-t } 2>/dev/null)

                if [ -z "$result" ]; then
                    echo "  (no response from MQTT broker)"
                    return 1
                fi

                echo "$result" | while IFS= read -r line; do
                    local topic="''${line%% *}"
                    local payload="''${line#* }"
                    local dev="''${topic#zigbee2mqtt/}"
                    local state=$(echo "$payload" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
                    local brightness=$(echo "$payload" | sed -n 's/.*"brightness":\([0-9]*\).*/\1/p')
                    if [ -n "$brightness" ]; then
                        printf "  %-25s %-5s (brightness: %s)\n" "$dev" "$state" "$brightness"
                    else
                        printf "  %-25s %-5s\n" "$dev" "$state"
                    fi
                done
            else
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sofaecke/decke_3/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sitzecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/sitzecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/trinkregal/n_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/trinkregal/n_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/elektro_ecke/decke_1/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/elektro_ecke/decke_2/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/spind/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
                mosquitto_pub -h "$mqtt_host" -t "zigbee2mqtt/3ddruck/wand/set" -m "{\"state\": \"ON\", \"brightness\": $1}"
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
