# Pi agent configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.home.gui.pi;
  pp = inputs.pi-packages.packages.${pkgs.system};

  # ponytail: Concise code skill & extension
  piPonytail = pp.pi-dietrichgebert-ponytail;

  # pi-lens: Real-time code feedback — LSP, linters, formatters, type-checking
  piLens = pp.pi-pi-lens;

  # pi-hermes-memory: Persistent memory + session search + secret scanning
  piHermesMemory = pp.pi-pi-hermes-memory;

  # billion-context: universal context-compression proxy for AI coding agents
  piBillionContext = pp.pi-billion-context;

  # bigpowers: 73 agent skills synthesizing software engineering discipline
  piBigpowers = pp.pi-bigpowers;

  # pi-web-access: web search, URL fetching, repo cloning, PDF/video extraction
  piWebAccess = pp.pi-pi-web-access;

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
    home.packages =
      (lib.optional (cfg.llmAgentsPackage != null) cfg.llmAgentsPackage)
      # bili: manage/launch the billion-context proxy (dist is self-contained, needs node)
      ++ [ (pkgs.writeShellScriptBin "bili" ''
        exec ${pkgs.nodejs}/bin/node ${piBillionContext}/dist/index.js "$@"
      '') ];

    # billion-context: context-compression proxy. The pi extension (registered
    # in settings.json `packages` below) is a thin client that connects to this
    # proxy and detects it from the /bili/-prefixed model baseURLs in
    # models.json. Without a running proxy it loads but compresses nothing —
    # that's why simply registering the package looked "not installed".
    systemd.user.services.billion-context = {
      Unit = {
        Description = "billion-context context-compression proxy";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${pkgs.nodejs}/bin/node ${piBillionContext}/dist/index.js --port 8787";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Register all pi packages declaratively in settings.json (pi's `packages`
    # mechanism). This is the correct way to install pi packages: pi reads each
    # package's `pi` manifest (extensions/skills/prompts), shows them as proper
    # packages in `pi list`/`pi config`, and groups resources correctly.
    #
    # NOTE: do NOT symlink whole package dirs into ~/.pi/agent/extensions/ — that
    # makes pi treat them as ad-hoc extension dirs, displaying fragment paths
    # ("dist", "src", "pi-extension"...) instead of the package, and exposes their
    # non-factory top-level index.js (e.g. bigpowers) which can crash pi at startup.
    #
    # Updates: since these come from the pi-packages flake input, bump that input
    # (nix flake lock --update-input pi-packages) + rebuild to get new versions.
    # Because settings.json is HOME-MANAGER-MANAGED here, do not also use `pi install`
    # (it would need a writable settings.json and npm); manage packages from this file.
    home.file.".pi/agent/settings.json".text = lib.mkIf cfg.extensions (builtins.toJSON {
      lastChangelogVersion = "1.4.0";
      # Retry backoff: the providers (KISSKI/IONOS via bili) rate-limit with a
      # 10s sliding window (2 req/10s) and put "Retry after N seconds" in the
      # body. Pi 1.4.0's agent-level retry is pure exponential backoff and does
      # NOT parse that hint (verified in the binary: retryDelayMs() ignores
      # Retry-After; pi-ai's header-honoring path needs retry.provider.maxRetries
      # > 0 but the SDK client is hard-coded to 0). The default 2s/4s/8s retries
      # all land inside the window and fail. A 12s base makes the first retry
      # land outside it: 12s, 24s, 48s, 60s (capped).
      retry = {
        enabled = true;
        maxRetries = 4;
        baseDelayMs = 12000;
      };
      packages = [
        (toString piLens)
        (toString piHermesMemory)
        (toString piPonytail)
        (toString piBillionContext)
        (toString piWebAccess)
        (toString piBigpowers)
      ];
    });

    # pi-web-access: web search, URL fetching, repo cloning, PDF/video extraction
    home.file.".pi/agent/extensions/pi-web-access" = lib.mkIf cfg.extensions {
      source = piWebAccess;
      recursive = true;
    };

    # sudo-askpass: local extension — permission-gated sudo using "sudo -A" via
    # kdialog askpass. The password is entered in a GUI dialog and never touches
    # the agent. See pi-extensions/sudo-askpass/index.ts. Deployed as a
    # single-file extension (pi loads direct .ts/.js files in extensions/).
    home.file.".pi/agent/extensions/sudo-askpass.ts" = lib.mkIf cfg.extensions {
      source = ./../../../pi-extensions/sudo-askpass/index.ts;
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
            "baseUrl": "http://localhost:8787/bili/https://chat-ai.academiccloud.de/v1",
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
                "input": ["text", "image"],
                "contextWindow": 268288,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3-omni-30b-a3b-instruct",
                "name": "Qwen 3 Omni 30B A3B (KISSKI)",
                "reasoning": false,
                "input": ["text", "image"],
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
                "input": ["text", "image"],
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
          },
          "ionos": {
            "baseUrl": "http://localhost:8787/bili/https://openai.inference.de-txl.ionos.com/v1",
            "api": "openai-completions",
            "apiKey": "!op read 'op://Personal/ionos basebox api cred/Anmeldedaten'",
            "models": [
              {
                "id": "Qwen/Qwen3.8-27B",
                "name": "Qwen3.8-27B",
                "reasoning": true,
                "input": ["text", "image"],
                "contextWindow": 262144,
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
