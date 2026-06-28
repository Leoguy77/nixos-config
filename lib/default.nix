# Shared utility functions and helpers
{ lib, ... }:

{
  # Helper to conditionally enable features
  mkIfFeature = feature: config: lib.mkIf (feature config) config;
  
  # Helper for optional package lists
  mkOptPackages = pkgs: packages: with pkgs; packages;
  
  # Common service template
  mkService = { name, enable ? true, package, ... }@args: {
    systemd.services.${name} = lib.mkIf enable {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${package}/bin/${name}";
        Restart = "on-failure";
      };
    };
  };
  
  # Helper for creating module options
  mkOpt = lib.mkOption;
  
  # Default text option
  mkOptText = default: description: {
    type = lib.types.str;
    inherit default description;
  };
  
  # Default boolean option
  mkOptBool = default: description: {
    type = lib.types.bool;
    inherit default description;
  };
  
  # Default package list option
  mkOptPackages = default: description: {
    type = lib.types.listOf lib.types.package;
    inherit default description;
  };
}
