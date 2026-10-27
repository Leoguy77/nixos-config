# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.gui.pi;
  pp = inputs.pi-packages.packages.${pkgs.system};

  # pi-ollama-cloud: Ollama Cloud model provider
  piOllamaCloud = pp.pi-pi-ollama-cloud;

  # ponytail: Concise code skill & extension
  piPonytail = pp.pi-dietrichgebert-ponytail;

  # pi-lens: Real-time code feedback — LSP, linters, formatters, type-checking
  piLens = pp.pi-pi-lens;

  # pi-simplify: Code clarity & maintainability review for recently changed code
  piSimplify = pp.pi-pi-simplify;

  # pi-hermes-memory: Persistent memory + session search + secret scanning
  piHermesMemory = pp.pi-pi-hermes-memory;

  # pi-archimedes-sudo: Safe privileged execution — sudo_exec tool with
  # masked password prompt + bash-sudo guard
  piArchimedesSudo = pp.pi-pi-archimedes-sudo;

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

    # pi-archimedes-sudo: Safe privileged execution — sudo_exec tool with
    # masked password prompt + bash-sudo guard
    home.file.".pi/agent/extensions/pi-archimedes-sudo" = lib.mkIf cfg.extensions {
      source = piArchimedesSudo;
      recursive = true;
    };

    # Custom model providers (KISSKI). Safe to commit: the 1Password CLI
    # command reads the actual API key at runtime, so no secret in the file.
    # Pi resolves !command at request time. Since 1Password caches the session,
    # only the first call per session prompts for approval; subsequent calls
    # are fast. No shell wrapper needed.
    home.file.".pi/agent/models.json".text = ''
      {
        "providers": {
          "kisski": {
            "baseUrl": "https://chat-ai.academiccloud.de/v1",
            "api": "openai-completions",
            "apiKey": "!op read 'op://gnh/Kisski/Kisski/API-Key'",
            "models": [
              {
                "id": "deepseek-v4-flash-0731",
                "name": "DeepSeek V4 Flash (KISSKI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.5-397b-a17b",
                "name": "Qwen 3.5 397B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.6-35b-a3b",
                "name": "Qwen 3.6 35B A3B (KISSKI)",
                "reasoning": false,
                "input": ["text", "image"],
                "contextWindow": 268288,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.8-27b",
                "name": "Qwen 3.8 27B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image", "video"],
                "contextWindow": 268288,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3-omni-30b-a3b-instruct",
                "name": "Qwen 3 Omni 30B A3B (KISSKI)",
                "reasoning": false,
                "input": ["text", "image", "audio"],
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3-coder-next",
                "name": "Qwen 3 Coder Next (KISSKI)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3-30b-a3b-instruct-2507",
                "name": "Qwen 3 30B A3B Instruct 2507 (KISSKI)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "glm-5.3-flash",
                "name": "GLM 5.3 Flash (KISSKI)",
                "reasoning": true,
                "input": ["text", "image", "video"],
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "gemma-4-31b-it",
                "name": "Gemma 4 31B Instruct (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "eurollm-22b-instruct-2512",
                "name": "EuroLLM 22B Instruct 2512 (KISSKI)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 1048576,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "meta-llama-3.1-8b-instruct",
                "name": "Meta Llama 3.1 8B Instruct (KISSKI)",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 131072,
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
