# System-wide packages
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.packages;
in

{
  options.modules.packages = {
    enable = lib.mkEnableOption "packages module";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra system-wide packages";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      [
        # Core utilities
        vim
        wget
        curl
        git

        # Deployment + secrets: `just deploy` / `just secrets` need these on the
        # normal PATH, otherwise every invocation has to be wrapped in
        # `nix develop .# --command …`.
        just
        sops
        ssh-to-pgp
        gnupg
        pinentry-curses # terminal PIN/passphrase prompt (works when GPG_TTY is set)
        pinentry-qt # GUI prompt — the agent can then ask for the card PIN from
        # contexts with no TTY (agent/tool shells, GUI apps, `git commit`)

        # System monitoring
        htop
        btop
        fastfetch # Replacement for unmaintained neofetch

        # File management
        unzip
        p7zip

        # User-provided extra packages
      ]
      ++ cfg.extraPackages;
  };
}
