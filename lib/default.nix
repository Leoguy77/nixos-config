# Shared utility functions and helpers
# Import this in modules via specialArgs as `mylib`
{ lib, ... }:

{
  # Helper to conditionally enable features
  mkIfFeature = feature: config: lib.mkIf (feature config) config;

  # Common service template
  mkService =
    {
      name,
      enable ? true,
      package,
      ...
    }:
    {
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
          (type == "directory")
          # Include directories
          || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name)) # Include .nix files except default.nix
        ) (builtins.readDir path)
      )
    );

  # Path helper - get path relative to flake root
  relativeToRoot = lib.path.append ../.;

  # Helper to merge attrsets recursively
  mergeAttrs = lib.attrsets.recursiveUpdate;

  # Register a DNS record without caring which host publishes the zone.
  #
  # A service module calls this to state "my hostname needs an A record"; the
  # host that owns the zone renders every registered record for it. Nothing is
  # published unless some host sets `modules.dns.push.enable` for that zone, so
  # this is safe to call from a module that is imported everywhere.
  #
  #   (mylib.publishDns { zone = "lsinfra.de"; text = ''A("mail", "192.0.2.1")''; })
  #
  # Two modules claiming the same name+type is a **build error**, not a silent
  # overwrite: dnscontrol rejects exact duplicate records at `check` time.
  publishDns =
    { zone, text }:
    {
      inherit zone text;
    };

  # Helper to create optional configurations
  mkOptionalConfig = condition: config: lib.mkIf condition config;

  # Helper for common option types
  types = {
    inherit (lib.types)
      str
      bool
      int
      float
      package
      packages
      listOf
      attrs
      submodule
      nullOr
      ;
  };
}
