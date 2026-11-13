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
          # ~/.ssh/GPG so the CLI can open secrets.sops.yaml (docs/SECRETS.md).
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
