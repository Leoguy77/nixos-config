# Nix daemon settings + GC.
#
# Single purpose: the Nix store/daemon configuration every NixOS box needs —
# experimental features, trusted users, automatic GC. Shared by desktops and
# servers (both previously re-declared this identical block).
{
  config,
  lib,
  myvars,
  ...
}:

let
  cfg = config.modules.nix;
in

{
  options.modules.nix = {
    enable = lib.mkEnableOption "nix daemon settings and GC";

    mainUser = lib.mkOption {
      type = lib.types.str;
      default = myvars.username;
      description = "User trusted to control the nix daemon.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Disabled: with useGlobalPkgs + bundles, nix-store --optimise on every
      # boot makes boot slow. GC is handled by the timer below.
      auto-optimise-store = false;
      # mkForce: the NixOS default is ["root"], which would otherwise be
      # concatenated into this list and write `trusted-users = root root …`.
      trusted-users = lib.mkForce [
        "root"
        cfg.mainUser
      ];
    };

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };
}
