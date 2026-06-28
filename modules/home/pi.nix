# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.pi;
in

{
  options.modules.home.pi = {
    enable = lib.mkEnableOption "pi home module";
    extensions = lib.mkEnableOption "pi extensions";
    llmAgentsPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "LLM agents package (from flake inputs)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pi agent packages from flake input if provided
    home.packages = lib.mkIf (cfg.llmAgentsPackage != null) [
      cfg.llmAgentsPackage
    ];

    # Pi extensions directory
    home.file.".pi-extensions" = lib.mkIf cfg.extensions {
      source = lib.mkDefault "${config.home.homeDirectory}/dotfiles/nixos-config/pi-extensions";
      recursive = true;
    };

    # Pi configuration
    xdg.configFile."pi/config.json".text = lib.mkDefault ''
      {
        "extensions": [],
        "skills": []
      }
    '';
  };
}
