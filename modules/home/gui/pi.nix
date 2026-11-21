# Pi agent configuration
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

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

  # pi-token-stats: token and cost statistics per session
  piTokenStats = pp.pi-pi-token-stats;

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
      ++ [
        (pkgs.writeShellScriptBin "bili" ''
          exec ${pkgs.nodejs}/bin/node ${piBillionContext}/dist/index.js "$@"
        '')
        # kisski-key: prints the current KISSKI API key from 1Password.
        # The key index lives in a counter file owned by the keyfailover
        # extension — this only reads it. Pi re-resolves models.json `!command`
        # apiKeys on every provider request, so after keyfailover advances the
        # counter the very next retry uses the next key. All three keys stay in
        # 1Password; nothing secret is on disk.
        (pkgs.writeShellScriptBin "kisski-key" ''
          n=$(cat "''${XDG_CACHE_HOME:-$HOME/.cache}/pi-kisski-key" 2>/dev/null || echo 0)
          # Field labels are inconsistent in 1Password (APi/API), so address
          # them by field id: stable, and renaming a field cannot break this.
          case "$n" in
            1) field='twnicdakxjacjnfsiuilfk2n2m' ;;
            2) field='vtcnpt2k43ixp5t6er6nj7btzi' ;;
            *) field='fzedhxi7av7sctch5o4u6httqi' ;;
          esac
          if key=$(op read "op://Personal/Academic Cloud/$field" 2>/dev/null); then
            echo "$key"
          else
            # Counter points at a field that no longer exists: fall back to key 1
            # rather than failing every request until the cache file is cleared.
            op read 'op://Personal/Academic Cloud/fzedhxi7av7sctch5o4u6httqi'
          fi
        '')
      ];

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
    home.file.".pi/agent/settings.json".text = lib.mkIf cfg.extensions (
      builtins.toJSON {
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
        # Compaction must fire well before the window edge. Pi estimates context
        # from raw char counts INCLUDING replayed thinking blocks
        # (estimateTokens2: `chars += block.thinking.length`), so on a long
        # session it believes it is at ~1.6M while the upstream -- which
        # normalizes reasoning away -- bills only ~155k. At the edge pi shrinks
        # the summary request's max_tokens to make input+output fit, which lands
        # at <=200; billion-context treats any request with
        # max_tokens<=200 as a "side request" and forwards it with ZERO
        # processing (index.js:57035 isSideRequest, bypass at 57433), so the
        # untrimmed body hits vLLM and overflows at 1048577. Reserving 400k
        # keeps compaction early enough that the summary request never takes
        # that bypass.
        compaction = {
          reserveTokens = 16384;
          keepRecentTokens = 20000;
          modelOverrides = {
            "kisski/deepseek-v4.1-flash-1017" = {
              reserveTokens = 400000;
            };
          };
        };
        packages = [
          (toString piLens)
          (toString piHermesMemory)
          (toString piPonytail)
          (toString piBillionContext)
          (toString piWebAccess)
          # bigpowers, minus its git guard. The package ships exactly one
          # extension, extensions/omp-hooks.ts, and that single file bundles three
          # unrelated concerns: destructive-git blocking, Conventional Commits
          # enforcement, and a hard refusal to commit on main/master. There is no
          # per-rule switch, and its combined-tool bypass (GIT_BIGPOWERS_LAND) is
          # read from PI'S OWN process env -- so exporting it inside a bash call
          # can never reach it. `extensions = [ ];` drops the file and keeps the
          # package's 80 skills and prompts, which is the whole point of having it.
          # Refusing commits on main is wrong for this repo: it is a solo config
          # where every change is one verified component committed directly, with
          # no reviewers to open a PR for. Conventional Commits and destructive-git
          # blocking were already covered before this package arrived (pre-commit
          # enforces the message shape; nothing here needed rescuing from a
          # force-push). Restore by putting `(toString piBigpowers)` back.
          {
            source = toString piBigpowers;
            extensions = [ ];
          }
          (toString piTokenStats)
        ];
      }
    );

    # sudo-askpass: local extension — permission-gated sudo using "sudo -A" via
    # kdialog askpass. The password is entered in a GUI dialog and never touches
    # the agent. See pi-extensions/sudo-askpass/index.ts. Deployed as a
    # single-file extension (pi loads direct .ts/.js files in extensions/).
    home.file.".pi/agent/extensions/sudo-askpass.ts" = lib.mkIf cfg.extensions {
      source = ./../../../pi-extensions/sudo-askpass/index.ts;
    };

    # keyfailover: advance the KISSKI key counter when a key is rejected.
    # Pi treats 401/403 as terminal and retries 429 on the same key, so this
    # rewrites those errors to a retryable one; the retry re-resolves
    # models.json's !command apiKey and picks up the next key.
    home.file.".pi/agent/extensions/keyfailover.ts" = lib.mkIf cfg.extensions {
      source = ./../../../pi-extensions/keyfailover/index.ts;
    };

    # Custom model providers (KISSKI). Safe to commit: the 1Password CLI
    # command reads the actual API key at runtime, so no secret in the file.
    # Pi re-resolves the !command on every provider request (verified: 4
    # requests -> 4 invocations), so kisski-key can switch keys between
    # attempts. The keyfailover extension advances that counter on 401/403/429,
    # which Pi would otherwise treat as terminal (401/403) or retry blindly on
    # the same key (429). All three keys stay in 1Password.
    home.file.".pi/agent/models.json".text = ''
      {
        "providers": {
          "kisski": {
            "baseUrl": "http://localhost:8787/bili/https://chat-ai.academiccloud.de/v1",
            "api": "openai-completions",
            "apiKey": "!kisski-key",
            "models": [
              {
                "id": "deepseek-v4-flash-0731",
                "name": "DeepSeek V4 Flash (KISSKI)",
                "reasoning": true,
                "thinkingLevelMap": {
                  "off": "none",
                  "minimal": null,
                  "low": "low",
                  "medium": null,
                  "high": "high",
                  "xhigh": null,
                  "max": "max"
                },
                "input": ["text"],
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "deepseek-v4.1-flash-1017",
                "name": "DeepSeek V4.1 Flash (KISSKI)",
                "reasoning": true,
                "thinkingLevelMap": {
                  "off": "none",
                  "minimal": null,
                  "low": "low",
                  "medium": "medium",
                  "high": "high",
                  "xhigh": null,
                  "max": "max"
                },
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "glm-5.3",
                "name": "GLM 5.3 (KISSKI)",
                "reasoning": true,
                "input": ["text"],
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "mistral-large-4-1t-a52b",
                "name": "Mistral Large 4 1T A52B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.5-397b-a17b",
                "name": "Qwen 3.5 397B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 262144,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.6-35b-a3b",
                "name": "Qwen 3.6 35B A3B (KISSKI)",
                "reasoning": false,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 268288,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3.8-27b",
                "name": "Qwen 3.8 27B (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 268288,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "qwen3-omni-30b-a3b-instruct",
                "name": "Qwen 3 Omni 30B A3B (KISSKI)",
                "reasoning": false,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
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
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
                "contextWindow": 1000000,
                "maxTokens": 16384,
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
              },
              {
                "id": "gemma-4-31b-it",
                "name": "Gemma 4 31B Instruct (KISSKI)",
                "reasoning": true,
                "input": ["text", "image"],
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
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
                "inputLimits": { "images": { "resize": { "maxWidth": 1280, "maxHeight": 1280, "maxBytes": 400000, "jpegQuality": 75 } } },
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
