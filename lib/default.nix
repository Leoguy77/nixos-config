# Shared utility functions and helpers
# Import this in modules via specialArgs as `mylib`
{ lib, ... }:

{
  # Helper to conditionally enable features
  mkIfFeature = feature: config: lib.mkIf (feature config) config;
  
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
  mkOptPkgs = default: description: {
    type = lib.types.listOf lib.types.package;
    inherit default description;
  };
  
  # Auto-scan all .nix files in a directory for imports
  # Usage: imports = mylib.scanPaths ./.;
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          name: type:
          (type == "directory") ||  # Include directories
          ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))  # Include .nix files except default.nix
        ) (builtins.readDir path)
      )
    );
  
  # Path helper - get path relative to flake root
  relativeToRoot = lib.path.append ../.;
  
  # Helper to merge attrsets recursively
  mergeAttrs = lib.attrsets.recursiveUpdate;
  
  # Helper to create optional configurations
  mkOptionalConfig = condition: config: lib.mkIf condition config;
  
  # Helper for common option types
  types = {
    inherit (lib.types) str bool int float package packages listOf attrs submodule nullOr;
  };
}
