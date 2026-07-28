# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.gui.pi;
  pp = inputs.pi-packages.packages.${pkgs.system};

  # pi-ollama-cloud: Ollama Cloud model provider
  piOllamaCloud = pp.pi-pi-ollama-cloud;

  # context-mode: Extended context window management
  piContextMode = pp.pi-context-mode;

  # ponytail: Concise code skill & extension
  piPonytail = pp.pi-dietrichgebert-ponytail;

  # pi-lens: Real-time code feedback — LSP, linters, formatters, type-checking
  piLens = pp.pi-pi-lens;

  # pi-simplify: Code clarity & maintainability review for recently changed code
  piSimplify = pp.pi-pi-simplify;

  # pi-hermes-memory: Persistent memory + session search + secret scanning
  piHermesMemory = pp.pi-pi-hermes-memory;

  # pi-token-speed: Tokens per second measurement via sliding window
  piTokenSpeed = pp.pi-pi-token-speed;

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
    home.packages = lib.optional (cfg.llmAgentsPackage != null) cfg.llmAgentsPackage;

    # pi-ollama-cloud installed as a Nix store-backed symlink in pi's extension
    # directory. Pi auto-discovers ~/.pi/agent/extensions/*/index.ts directories
    # and loads them as extensions — no settings.json changes needed, no risk of
    # clobbering user settings, works with `pi install` CLI commands.
    home.file.".pi/agent/extensions/pi-ollama-cloud" = lib.mkIf cfg.extensions {
      source = piOllamaCloud;
      recursive = true;
    };

    # context-mode installed as a directory (for module resolution) plus a .ts bridge
    # file as the pi extension entry point. Pi discovers *.ts files at the root of the
    # extensions directory — not subdirectories without index.ts.
    home.file.".pi/agent/extensions/context-mode" = lib.mkIf cfg.extensions {
      source = piContextMode;
      recursive = true;
    };

    # Bridge entry point: pi loads this as a single-file extension; the re-export
    # resolves to the context-mode directory next to it.
    home.file.".pi/agent/extensions/context-mode.ts".text = ''
      export { default } from "./context-mode/build/adapters/pi/extension.js";
    '';

    # pi-lens: Real-time code feedback — LSP, linters, formatters, type-checking
    home.file.".pi/agent/extensions/pi-lens" = lib.mkIf cfg.extensions {
      source = piLens;
      recursive = true;
    };

    # pi-simplify: Code clarity & maintainability review
    home.file.".pi/agent/extensions/pi-simplify" = lib.mkIf cfg.extensions {
      source = piSimplify;
      recursive = true;
    };

    # pi-hermes-memory: Persistent memory + session search + secret scanning
    home.file.".pi/agent/extensions/pi-hermes-memory" = lib.mkIf cfg.extensions {
      source = piHermesMemory;
      recursive = true;
    };

    # pi-token-speed: Tokens per second measurement via sliding window
    home.file.".pi/agent/extensions/pi-token-speed" = lib.mkIf cfg.extensions {
      source = piTokenSpeed;
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
            "apiKey": "$KISSKI_API_KEY",
            "models": [
              {
                "id": "qwen3.5-397b-a17b",
                "name": "Qwen 3.5 397B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "contextWindow": 256000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "deepseek-v4-flash",
                "name": "DeepSeek V4 Flash (KISSKI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1000000,
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
