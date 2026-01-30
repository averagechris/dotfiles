{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.users.chrisMinimal
    inputs.nixos-modules.nixosModules.isRemoteBuilder
    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
    ./hardware.nix
    ./disko.nix
  ];

  # Boot configuration (systemd-boot for UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "trainwreck";
  networking.networkmanager.enable = false;

  # Timezone
  time.timeZone = "America/New_York";

  # SSH server
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Passwordless sudo for deploy-rs
  dotfiles.sudoNoPassword.enable = true;

  # Agenix secrets
  age.secrets = {
    telegram-bot-token = {
      file = ../../../secrets/trainwreck/telegram-bot-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    telegram-bot-token-staging = {
      file = ../../../secrets/trainwreck/telegram-bot-token-staging.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    telegram-user-ids = {
      file = ../../../secrets/trainwreck/telegram-user-ids.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    openrouter-api-key = {
      file = ../../../secrets/trainwreck/openrouter-api-key.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    kagi-api-token = {
      file = ../../../secrets/trainwreck/kagi-api-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    gateway-auth-token = {
      file = ../../../secrets/trainwreck/gateway-auth-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    imgflip-username = {
      file = ../../../secrets/trainwreck/imgflip-username.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    imgflip-password = {
      file = ../../../secrets/trainwreck/imgflip-password.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
  };

  environment.systemPackages = with pkgs; [
    htop
    tmux
    curl
    jq
    ungoogled-chromium # For moltbot browser support
  ];

  system.stateVersion = "25.11";

  # Home Manager configuration for chris
  home-manager.users.chris = {...}: {
    home.stateVersion = "25.11";

    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.nix-clawdbot.homeManagerModules.moltbot
    ];

    # Moltbot configuration
    programs.moltbot = {
      documents = ./clawdbot-documents;
      firstParty = {
        summarize.enable = true;
        sag.enable = true; # Text-to-speech
        oracle.enable = false; # Using kagi-search instead
        # Disabled: no screen on headless server
        peekaboo.enable = false;
      };
      instances.default = {
        enable = true;
        agent.model = "openrouter/moonshotai/kimi-k2-0905";
        gateway.authTokenFile = config.age.secrets.gateway-auth-token.path;
        providers.openrouter.apiKeyFile = config.age.secrets.openrouter-api-key.path;
        providers.telegram = {
          enable = true;
          botTokenFile = config.age.secrets.telegram-bot-token.path;
          allowFromFile = config.age.secrets.telegram-user-ids.path;
          groups = {
            "*" = {requireMention = true;};
            "-4996214260" = {requireMention = false;};
          };
        };
        systemd.enable = true;
        launchd.enable = false;
        # Enable local extensions from clawdbot-extensions/
        configOverrides = {
          # Register custom models not yet in moltbot's built-in registry
          models = {
            mode = "merge";
            providers.openrouter = {
              baseUrl = "https://openrouter.ai/api/v1";
              api = "openai-responses";
              models = [
                {
                  id = "moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                  api = "openai-responses";
                  reasoning = true;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2";
                  name = "Kimi K2";
                  api = "openai-responses";
                  reasoning = false;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2-0905";
                  name = "Kimi K2 0905";
                  api = "openai-responses";
                  reasoning = false;
                  input = ["text"];
                  contextWindow = 262144;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2-thinking";
                  name = "Kimi K2 Thinking";
                  api = "openai-responses";
                  reasoning = true;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 16000;
                }
              ];
            };
          };
          # Model catalog for /model command
          agents.defaults.models = {
            "openrouter/moonshotai/kimi-k2.5" = {alias = "K2.5";};
            "openrouter/moonshotai/kimi-k2" = {alias = "K2";};
            "openrouter/moonshotai/kimi-k2-0905" = {alias = "K2 Stable";};
            "openrouter/moonshotai/kimi-k2-thinking" = {alias = "K2 Think";};
            "openrouter/anthropic/claude-opus-4.5" = {alias = "Opus";};
            "openrouter/anthropic/claude-sonnet-4.5" = {alias = "Sonnet";};
            "openrouter/openai/gpt-5.2-mini" = {alias = "GPT Mini";};
            "openrouter/openai/gpt-5.2-codex" = {alias = "Codex";};
            "openrouter/google/gemini-2.5-flash" = {alias = "Gemini";};
          };
          # Tell moltbot where to find local plugins
          plugins.load.paths = ["/home/chris/.moltbot/extensions"];
          plugins.entries."kagi-search" = {
            enabled = true;
          };
          plugins.entries."meme-generator" = {
            enabled = true;
          };
          plugins.entries."image-generator" = {
            enabled = true;
          };
          plugins.entries."opencode-delegate" = {
            enabled = true;
          };
          # Enable LanceDB memory plugin (semantic search, auto-recall, auto-capture)
          plugins.slots.memory = "memory-lancedb";
          plugins.entries."memory-lancedb" = {
            enabled = true;
            config = {
              embedding = {
                # Uses OPENAI_BASE_URL env var to point to OpenRouter
                # API key is read from file at runtime
                apiKey = "\${OPENROUTER_API_KEY}";
                model = "text-embedding-3-small";
              };
              autoRecall = true;
              autoCapture = true;
            };
          };
          # Browser configuration for headless server
          browser = {
            enabled = true;
            headless = true;
            noSandbox = true; # Required for headless/server environments
            executablePath = "${pkgs.ungoogled-chromium}/bin/chromium";
            defaultProfile = "clawd"; # Use managed browser, not extension relay
            profiles.clawd = {
              cdpPort = 18800;
              color = "#FF4500"; # Required field
            };
          };
        };
        plugins = [
          # { source = "github:moltbot/nix-steipete-tools?dir=tools/summarize"; }
        ];
      };

      # Staging instance for testing configuration changes before deploying to main
      instances.staging = {
        enable = true;
        agent.model = "openrouter/moonshotai/kimi-k2-0905";
        gateway.authTokenFile = config.age.secrets.gateway-auth-token.path;
        gateway.port = 18081; # Different port from default (18080)
        providers.openrouter.apiKeyFile = config.age.secrets.openrouter-api-key.path;
        providers.telegram = {
          enable = true;
          botTokenFile = config.age.secrets.telegram-bot-token-staging.path;
          allowFromFile = config.age.secrets.telegram-user-ids.path;
          groups = {
            "*" = {requireMention = true;};
          };
        };
        systemd.enable = true;
        launchd.enable = false;
        # Same config as default - modify here to test changes
        configOverrides = {
          # Register custom models not yet in moltbot's built-in registry
          models = {
            mode = "merge";
            providers.openrouter = {
              baseUrl = "https://openrouter.ai/api/v1";
              api = "openai-responses";
              models = [
                {
                  id = "moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                  api = "openai-responses";
                  reasoning = true;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2";
                  name = "Kimi K2";
                  api = "openai-responses";
                  reasoning = false;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2-0905";
                  name = "Kimi K2 0905";
                  api = "openai-responses";
                  reasoning = false;
                  input = ["text"];
                  contextWindow = 262144;
                  maxTokens = 8192;
                }
                {
                  id = "moonshotai/kimi-k2-thinking";
                  name = "Kimi K2 Thinking";
                  api = "openai-responses";
                  reasoning = true;
                  input = ["text"];
                  contextWindow = 131072;
                  maxTokens = 16000;
                }
              ];
            };
          };
          # Model catalog for /model command
          agents.defaults.models = {
            "openrouter/moonshotai/kimi-k2.5" = {alias = "K2.5";};
            "openrouter/moonshotai/kimi-k2" = {alias = "K2";};
            "openrouter/moonshotai/kimi-k2-0905" = {alias = "K2 Stable";};
            "openrouter/moonshotai/kimi-k2-thinking" = {alias = "K2 Think";};
            "openrouter/anthropic/claude-opus-4.5" = {alias = "Opus";};
            "openrouter/anthropic/claude-sonnet-4.5" = {alias = "Sonnet";};
            "openrouter/openai/gpt-5.2-mini" = {alias = "GPT Mini";};
            "openrouter/openai/gpt-5.2-codex" = {alias = "Codex";};
            "openrouter/google/gemini-2.5-flash" = {alias = "Gemini";};
          };
          # Tell moltbot where to find local plugins
          plugins.load.paths = ["/home/chris/.moltbot-staging/extensions"];
          plugins.entries."kagi-search" = {
            enabled = true;
          };
          plugins.entries."meme-generator" = {
            enabled = true;
          };
          plugins.entries."image-generator" = {
            enabled = true;
          };
          plugins.entries."opencode-delegate" = {
            enabled = true;
          };
          # Enable LanceDB memory plugin (semantic search, auto-recall, auto-capture)
          plugins.slots.memory = "memory-lancedb";
          plugins.entries."memory-lancedb" = {
            enabled = true;
            config = {
              embedding = {
                apiKey = "\${OPENROUTER_API_KEY}";
                model = "text-embedding-3-small";
              };
              autoRecall = true;
              autoCapture = true;
            };
          };
          # Browser configuration for headless server
          browser = {
            enabled = true;
            headless = true;
            noSandbox = true;
            executablePath = "${pkgs.ungoogled-chromium}/bin/chromium";
            defaultProfile = "clawd-staging";
            profiles.clawd-staging = {
              cdpPort = 18801; # Different port from default
              color = "#00BFFF"; # Different color to distinguish
            };
          };
        };
        plugins = [];
      };
    };

    # Add OPENAI_BASE_URL for memory-lancedb to use OpenRouter embeddings
    # The nix-clawdbot wrapper already handles OPENROUTER_API_KEY from apiKeyFile
    systemd.user.services.moltbot-gateway.Service.Environment = [
      "OPENAI_BASE_URL=https://openrouter.ai/api/v1"
    ];
    systemd.user.services.moltbot-staging.Service.Environment = [
      "OPENAI_BASE_URL=https://openrouter.ai/api/v1"
    ];

    # Set up extensions symlink for staging instance
    home.activation.moltbot-staging-extensions = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p $HOME/.moltbot-staging
      if [ ! -L $HOME/.moltbot-staging/extensions ]; then
        ln -sf $HOME/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions $HOME/.moltbot-staging/extensions
      fi
    '';

    # Minimal shell setup for server
    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = false;
    };

    # Disable programs that require flake inputs not available on this host
    programs.helix.enable = lib.mkForce false;

    # Enable jj and opencode
    programs.jujutsu.enable = true;
    programs.opencode.enable = true;
    programs.starship.enable = false;
  };
}
