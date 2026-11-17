# Administrative account + root identity.
#
# Single purpose: the set of keys and users that can administer this box.
# Every other server module that needs "who is the admin" reads
# `modules.accounts.{adminKeys,mainUser}` instead of re-declaring it.
{
  config,
  pkgs,
  lib,
  myvars,
  ...
}:

let
  cfg = config.modules.accounts;
in

{
  options.modules.accounts = {
    enable = lib.mkEnableOption "the administrative account and root SSH identity";

    adminKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys allowed to log in as root and as {option}`modules.accounts.mainUser`.";
    };

    mainUser = lib.mkOption {
      type = lib.types.str;
      default = myvars.username;
      description = "Administrative (wheel) user.";
    };

    # Passwordless sudo so key-only access is not locked out by a password
    # prompt the account does not have.
    passwordlessSudo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Grant `mainUser` passwordless sudo.";
    };
  };

  config = lib.mkIf cfg.enable {
    # mkDefault, not mkForce: the password now comes from modules.login on
    # desktops and from this module on servers. With a plain `false` here and
    # login.nix also setting `false`, merging would abort on a conflicting
    # definition of the same value.
    users.mutableUsers = lib.mkDefault false;

    users.users.root.openssh.authorizedKeys.keys = cfg.adminKeys;

    users.users.${cfg.mainUser} = {
      isNormalUser = true;
      description = myvars.fullName;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = cfg.adminKeys;
    };

    programs.zsh.enable = true;

    security.sudo = {
      enable = true;
      # Access is key-only and the account has no password, so a password
      # prompt would just lock the admin out.
      wheelNeedsPassword = !cfg.passwordlessSudo;
      execWheelOnly = true;
    };
  };
}
