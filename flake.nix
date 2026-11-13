{
  description = "Leon's NixOS System Configuration";

  # Binary cache configuration for faster builds
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://nix-cache.lsinfra.de/pi-packages"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "pi-packages:OF+SNU2ALJB8M+cQP/RfFOuKIOMN0w4WiV8k01pvUC4="
    ];
  };

  inputs = {
    # NixOS unstable channel (primary)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # NixOS stable channel (for critical packages)
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM Agents
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Auto CPU Frequency (power management)
    auto-cpufreq.url = "github:AdnanHodzic/auto-cpufreq";

    # Pre-commit hooks for code quality
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management with sops (sops-nix)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # pi.dev packages (Nix-native, from npm tarballs)
    pi-packages = {
      url = "github:Leoguy77/pi-packages.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disk management for nixos-anywhere deployments
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative mail stack: Postfix + Dovecot + rspamd + DKIM, all in Nix.
    # GitLab, not GitHub (the GitHub repo is dead). Branch `main` tracks
    # nixos-unstable-small and reports mailserverRelease 26.11, matching this
    # flake's nixpkgs — a mismatch is only a warning, but no need to silence it.
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      # System architecture
      system = "x86_64-linux";

      # Import pkgs with config
      # NOTE: Overlays are managed per-host in host configs (hosts/<host>/default.nix)
      # via nixpkgs.overlays, so they apply to both NixOS system and Home Manager
      # when useGlobalPkgs = true. See nixos-best-practices skill for details.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Import stable pkgs for critical packages
      pkgs-stable = import inputs.nixpkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };

      # Import custom lib and vars
      mylib = import ./lib { inherit (nixpkgs) lib; };
      myvars = import ./vars { inherit (nixpkgs) lib; };

      # Shared special arguments for all configurations
      specialArgs = {
        inherit
          inputs
          mylib
          myvars
          pkgs-stable
          ;
        sops-nix = inputs."sops-nix";
      };

      # Helper: create a NixOS host config from hosts/<name>/
      mkHost =
        hostname:
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            home-manager.nixosModules.home-manager
            inputs.auto-cpufreq.nixosModules.default
            inputs.nixos-mailserver.nixosModules.mailserver
            ./hosts/${hostname}
          ];
        };

      # Auto-discover hosts: every directory under hosts/ with a default.nix
      hostDirs = builtins.readDir ./hosts;
      hosts = builtins.filter (
        name: hostDirs.${name} == "directory" && builtins.pathExists ./hosts/${name}/default.nix
      ) (builtins.attrNames hostDirs);

      # Bootable installer ISO carrying one host's static networking and admin
      # key, for machines nixos-anywhere's kexec image cannot bootstrap (needs
      # 1.5 GB RAM; its --no-disko-deps fallback wants tools it does not ship).
      # Only for hosts that actually have a static address + gateway in vars/;
      # a laptop has nothing to bake in.
      isoHosts = builtins.filter (name: (myvars.networking.hostsAddr.${name} or { }) ? ipv4Gateway) hosts;

      mkInstallerIso =
        hostname:
        (nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./modules/iso/installer.nix
            {
              modules.isoInstaller = {
                enable = true;
                inherit hostname;
              };
            }
          ];
        }).config.system.build.isoImage;

    in
    {
      # NixOS configurations — auto-discovered from hosts/<name>/default.nix
      nixosConfigurations = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = mkHost name;
        }) hosts
      );

      # `nix build .#installerIso-mail` — a ready-to-upload installer for that
      # host. Only the hosts with a static address get one.
      packages.${system} = builtins.listToAttrs (
        map (name: {
          name = "installerIso-${name}";
          value = mkInstallerIso name;
        }) isoHosts
      );

      # Home Manager standalone configurations — only for hosts that actually
      # carry a home.nix (servers usually do not).
      homeConfigurations =
        let
          mkHome =
            hostname:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./modules/home
                ./hosts/${hostname}/home.nix
              ];
              extraSpecialArgs = specialArgs;
            };
          homeHosts = builtins.filter (name: builtins.pathExists ./hosts/${name}/home.nix) hosts;
        in
        builtins.listToAttrs (
          map (name: {
            name = "leoguy77@${name}";
            value = mkHome name;
          }) homeHosts
        );

      # Development shell with essential tools
      devShells.${system}.default = pkgs.mkShell {
        name = "nixos-config";
        packages = with pkgs; [
          # Nix formatting & linting
          nixfmt-rfc-style # Replaced nixfmt-classic (removed from nixpkgs)
          deadnix
          statix
          alejandra

          # Git tools
          git

          # Recipe runner for the justfile (deploy, iso, secrets).
          just

          # Secrets: deploy.sh derives the initrd bootstrap key from sops when it
          # is on PATH. ssh-to-pgp + gnupg are how you derive the PGP key from
          # ~/.ssh/GPG so the CLI can open secrets.sops.yaml (secrets/README.md).
          sops
          ssh-to-pgp
          gnupg

          # Optional: pre-commit hooks
          # pre-commit-hooks
        ];

        shellHook =
          # Installs .git/hooks/pre-commit on shell entry, so these checks run
          # locally instead of only under `nix flake check`.
          self.checks.${system}.pre-commit-check.shellHook + ''
            echo "🔧 NixOS Configuration Development Shell"
            echo "========================================="
            echo ""
            echo "Available tools:"
            echo "  - nixfmt-rfc-style: Format Nix files"
            echo "  - deadnix: Detect unused Nix code"
            echo "  - statix: Lint Nix files"
            echo "  - alejandra: Alternative Nix formatter"
            echo ""
            echo "Quick commands:"
            echo "  just                 # List the justfile recipes"
            echo "  just deploy root@ip  # Install a host"
            echo "  just iso mail        # Build its installer ISO"
            echo "  nix fmt              # Format all Nix files"
            echo "  nix flake check      # Check configuration"
            echo "  nix build            # Build configuration"
            echo ""
          '';
      };

      # Pre-commit checks for code quality
      checks.${system}.pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          # Nix formatting
          nixfmt = {
            enable = true;
            settings.width = 100;
          };

          # Detect unused Nix code
          deadnix.enable = true;

          # Lint Nix files
          statix.enable = true;

          # Refuse to create an unsigned commit. Runs at commit-msg because that
          # is the last stage before git writes the object: by post-commit the
          # commit already exists and a hook can no longer stop it.
          #
          # Two checks, because either one alone is bypassable:
          #   - commit.gpgsign must be true. This catches `git -c
          #     commit.gpgsign=false commit`, since -c changes what the hook reads.
          #   - the command line must not carry --no-gpg-sign, which leaves the
          #     config saying `true` while git skips signing anyway (verified).
          #     That flag is only visible in argv, so one of us has to walk the
          #     process chain: git -> hook template -> pre-commit -> this script.
          #
          # `git commit --no-verify` still skips every hook in this file. That is
          # git's own escape hatch and cannot be closed from inside a repository;
          # the airtight check is GitHub branch protection (Require signed
          # commits), which also catches a push from a machine without this hook.
          signed-commits = {
            enable = true;
            name = "signed commits only";
            stages = [ "commit-msg" ];
            pass_filenames = false;
            always_run = true;
            entry = toString (
              pkgs.writeShellScript "require-signed-commit" ''
                set -u

                fail() {
                  printf '\n\033[31m\u2717 unsigned commits are not allowed\033[0m\n  %s\n\n' "$1" >&2
                  exit 1
                }

                [ "$(git config --get commit.gpgsign)" = "true" ] \
                  || fail "signing is off for this commit. Re-enable it with: git config commit.gpgsign true"

                # Walk ancestors looking for the `git` process that spawned us
                # and inspect only ITS argv. Field 4 of /proc/PID/stat is the
                # ppid; `stat -c %P` does NOT work on procfs and silently yields
                # empty, which would stop the walk after one step.
                #
                # Only git's own argv is checked. Matching the whole chain would
                # be wrong: a shell running a script that merely mentions the
                # flag has it inside one big `bash -c …` argument, so every
                # innocent commit from such a shell would be refused.
                pid=$PPID
                for _ in $(seq 1 10); do
                  [ -r "/proc/$pid/stat" ] || break
                  # comm (field 2) may contain spaces and parens, so strip up to
                  # the LAST ') ' before splitting the remaining fields.
                  rest=$(< "/proc/$pid/stat")
                  rest=''${rest##*') '}
                  set -- $rest
                  ppid=''${2:-1}

                  argv0=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n1)
                  if [ "''${argv0##*/}" = git ]; then
                    # NUL-separated argv -> single space-padded line, so the
                    # match is one whole argument and not a substring.
                    args=" $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) "
                    case "$args" in
                      *" --no-gpg-sign "*) fail "git commit --no-gpg-sign is blocked. Drop the flag." ;;
                    esac
                    break
                  fi

                  [ "$ppid" -gt 1 ] || break
                  pid=$ppid
                done
              ''
            );
          };

          # Spell checker (optional)
          # typos = {
          #   enable = true;
          #   settings = {
          #     write = true;
          #     configPath = ".typos.toml";
          #   };
          # };
        };
      };

      # Formatter for nix fmt. Must be nixfmt-tree, not bare nixfmt: `nix fmt`
      # passes its arguments through, and with none given the bare nixfmt reads
      # *stdin* and dies on the empty expression. nixfmt-tree walks the tree
      # instead, which is what the command is actually for.
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
