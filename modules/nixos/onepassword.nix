# 1Password with proper NixOS system integration
#
# On NixOS the 1Password desktop-app integration (CLI `op` and browser
# unlock) requires a setuid-wrapped helper, a polkit policy, and the
# `onepassword`/`onepassword-cli` groups. These are ONLY provided by the
# programs._1password* modules. Installing 1Password via home.packages is
# not enough — `op read` fails with "connecting to desktop app:
# connection reset" because the app cannot verify the calling binary.
{ config, pkgs, lib, myvars, ... }:

let
  cfg = config.modules.onepassword;
in
{
  options.modules.onepassword = {
    enable = lib.mkEnableOption "1Password with system integration";

    polkitOwners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ myvars.username ];
      description = "Users allowed to authenticate 1Password via polkit.";
    };
  };

  config = lib.mkIf cfg.enable {
    # System 1Password CLI (`op`) — registers the onepassword-cli group and
    # the app-integration handshake.
    programs._1password.enable = true;

    # System 1Password GUI — installs the setuid BrowserSupport helper and
    # the polkit policy needed for desktop-app CLI/browser integration.
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = cfg.polkitOwners;
    };
  };
}
