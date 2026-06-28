# User accounts configuration
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.users;
in

{
  options.modules.users = {
    enable = lib.mkEnableOption "users module";
    mainUser = lib.mkOption {
      type = lib.types.str;
      default = "leoguy77";
      description = "Main user account name";
    };
    userShell = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zsh;
      description = "Default user shell";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user group
    users.groups.${cfg.mainUser} = { };

    # Define a user account
    users.users.${cfg.mainUser} = {
      isNormalUser = true;
      description = lib.mkDefault "Leon";
      extraGroups = [ 
        "networkmanager" 
        "wheel" 
        "input"
        cfg.mainUser
      ];
      shell = cfg.userShell;
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;
  };
}
