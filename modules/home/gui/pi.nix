# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.gui.pi;

  # pi-ollama-cloud: Tier A pi package (no runtime deps, only peer deps on pi core)
  # https://www.npmjs.com/package/pi-ollama-cloud v0.7.0
  # https://pi.dev/packages/pi-ollama-cloud
  #
  # Registers Ollama Cloud as a model provider with dynamically fetched models,
  # and provides ollama_web_search / ollama_web_fetch tools.
  ollamaCloudSrc = pkgs.fetchurl {
    url = "https://registry.npmjs.org/pi-ollama-cloud/-/pi-ollama-cloud-0.7.0.tgz";
    hash = "sha256-yfUlBnbNgPLtwE3jfFn8n20WF3Eu8xvdVNG/u5I+Lio=";
  };

  piOllamaCloud = pkgs.runCommand "pi-pkg-ollama-cloud" { nativeBuildInputs = [ pkgs.gnutar ]; } ''
    mkdir -p $out
    tar -xzf ${ollamaCloudSrc} --strip-components=1 -C $out
  '';

in

{
  options.modules.home.gui.pi = {
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

    # pi-ollama-cloud installed as a Nix store-backed symlink in pi's extension
    # directory. Pi auto-discovers ~/.pi/agent/extensions/*/index.ts directories
    # and loads them as extensions — no settings.json changes needed, no risk of
    # clobbering user settings, works with `pi install` CLI commands.
    home.file.".pi/agent/extensions/pi-ollama-cloud" = lib.mkIf cfg.extensions {
      source = piOllamaCloud;
      recursive = true;
    };
  };
}
