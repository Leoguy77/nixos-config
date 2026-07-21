# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.gui.pi;
  pp = inputs.pi-packages.packages.${pkgs.system};

  # pi-ollama-cloud: Ollama Cloud model provider
  piOllamaCloud = pp.pi-pi-ollama-cloud;

  # ponytail: Concise code skill & extension
  piPonytail = pp.pi-dietrichgebert-ponytail;

  # noheadroom: Headroom context compression bridge
  piNoheadroom = pp.pi-raquezha-noheadroom;

  # headroom-ai: context compression proxy server (needs --option sandbox false)
  headroom = pkgs.stdenv.mkDerivation {
    name = "headroom-ai-0.32.1";
    buildInputs = [ pkgs.python3 pkgs.python3.pkgs.pip pkgs.python3.pkgs.setuptools pkgs.python3.pkgs.wheel ];
    buildCommand = ''
      export HOME=$TMPDIR
      mkdir -p $out/bin
      pip install --no-input --no-cache-dir --prefix=$out "headroom-ai[proxy]==0.32.1"
    '';
    __noChroot = true;
    meta.description = "Context Optimization Layer for LLM Applications";
  };


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
    home.packages = (lib.optional (cfg.llmAgentsPackage != null) cfg.llmAgentsPackage)
      ++ lib.optionals cfg.extensions [ headroom ];

    # pi-ollama-cloud installed as a Nix store-backed symlink in pi's extension
    # directory. Pi auto-discovers ~/.pi/agent/extensions/*/index.ts directories
    # and loads them as extensions — no settings.json changes needed, no risk of
    # clobbering user settings, works with `pi install` CLI commands.
    home.file.".pi/agent/extensions/pi-ollama-cloud" = lib.mkIf cfg.extensions {
      source = piOllamaCloud;
      recursive = true;
    };

    # Custom model providers (KISSKI). Safe to commit: the 1Password CLI
    # command reads the actual API key at runtime, so no secret in the file.
    home.file.".pi/agent/models.json".text = ''
      {
        "providers": {
          "kisski": {
            "baseUrl": "https://chat-ai.academiccloud.de/v1",
            "api": "openai-completions",
            "apiKey": "!op read 'op://gnh/Kisski/Kisski/API-Key'",
            "models": [
              {
                "id": "qwen3.5-397b-a17b",
                "name": "Qwen 3.5 397B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "contextWindow": 128000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "deepseek-v4-flash",
                "name": "DeepSeek V4 Flash (KISSKI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 128000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              }
            ]
          }
        }
      }
    '';
  };
}
