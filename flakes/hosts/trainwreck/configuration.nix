{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  nixosConfig = config;

  # Shared base configuration for openclaw instances
  baseInstance = {
    enable = true;
    agent.model = "openrouter/moonshotai/kimi-k2-0905";
    gateway.authTokenFile = nixosConfig.age.secrets.gateway-auth-token.path;
    providers.openrouter.apiKeyFile = nixosConfig.age.secrets.openrouter-api-key.path;
    providers.telegram = {
      enable = true;
      allowFromFile = nixosConfig.age.secrets.telegram-user-ids.path;
      groups."*" = {requireMention = true;};
    };
    # Session isolation: each DM peer gets their own session
    # identityLinks allows linking accounts across platforms to share a session
    session = {
      dmScope = "per-peer";
      identityLinks = {
        chris = ["telegram:7281917558"];
      };
    };
    systemd.enable = true;
    launchd.enable = false;
    plugins = [];
  };

  # Shared configOverrides for both instances
  baseConfigOverrides = {
    # Model catalog for /model command
    # Note: Removed custom model definitions - let openclaw use its defaults
    # to avoid API format issues (openai-responses vs openai-chat)
    agents.defaults.models = {
      # Anthropic
      "openrouter/anthropic/claude-opus-4.5" = {alias = "Opus";};
      "openrouter/anthropic/claude-sonnet-4.5" = {alias = "Sonnet";};
      "openrouter/anthropic/claude-haiku-4.5" = {alias = "Haiku";};
      "openrouter/anthropic/claude-3.5-haiku" = {alias = "Haiku 3.5";};
      # OpenAI
      "openrouter/openai/gpt-5.2-codex" = {alias = "Codex";};
      "openrouter/openai/gpt-5.2" = {alias = "GPT 5.2";};
      "openrouter/openai/gpt-5-mini" = {alias = "GPT Mini";};
      "openrouter/openai/gpt-5-nano" = {alias = "GPT Nano";};
      # Google
      "openrouter/google/gemini-2.5-flash" = {alias = "Gemini";};
      # Mistral
      "openrouter/mistralai/mistral-large-2512" = {alias = "Mistral Large";};
      "openrouter/mistralai/mistral-medium-3.1" = {alias = "Mistral Medium";};
      "openrouter/mistralai/devstral-2512" = {alias = "Devstral";};
      "openrouter/mistralai/codestral-2508" = {alias = "Codestral";};
      # Kimi
      "openrouter/moonshotai/kimi-k2.5" = {alias = "K2.5";};
      "openrouter/moonshotai/kimi-k2-0905" = {alias = "K2";};
      "openrouter/moonshotai/kimi-k2-thinking" = {alias = "K2 Think";};
    };
    # Plugin configuration
    plugins.entries."kagi-search".enabled = true;
    plugins.entries."meme-generator".enabled = true;
    plugins.entries."image-generator".enabled = true;
    plugins.entries."opencode-delegate".enabled = true;
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
    };
  };
in {
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
      file = ../../../secrets/openrouter-api-key.age;
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
    # Grem personality documents (contain personal info)
    grem-agents = {
      file = ../../../secrets/trainwreck/grem-AGENTS.md.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    grem-soul = {
      file = ../../../secrets/trainwreck/grem-SOUL.md.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    grem-tools = {
      file = ../../../secrets/trainwreck/grem-TOOLS.md.age;
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
    ungoogled-chromium # For openclaw browser support
  ];

  system.stateVersion = "25.11";

  # Home Manager configuration for chris
  home-manager.users.chris = {
    lib,
    config,
    ...
  }: let
    hmLib = lib;
    hmConfig = config;
  in {
    home.stateVersion = "25.11";

    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.nix-openclaw.homeManagerModules.openclaw
    ];

    # Openclaw configuration
    programs.openclaw = {
      # Documents are encrypted with agenix (contain personal info)
      documentsRuntime = {
        agentsFile = nixosConfig.age.secrets.grem-agents.path;
        soulFile = nixosConfig.age.secrets.grem-soul.path;
        toolsFile = nixosConfig.age.secrets.grem-tools.path;
      };
      firstParty = {
        summarize.enable = true;
        sag.enable = true; # Text-to-speech
        oracle.enable = false; # Using kagi-search instead
        # Disabled: no screen on headless server
        peekaboo.enable = false;
      };

      # Grem - production instance
      instances.grem = lib.recursiveUpdate baseInstance {
        providers.telegram.botTokenFile = nixosConfig.age.secrets.telegram-bot-token.path;
        providers.telegram.groups."-4996214260" = {requireMention = false;};
        configOverrides = lib.recursiveUpdate baseConfigOverrides {
          plugins.load.paths = ["/home/chris/.openclaw-grem/extensions"];
          browser.defaultProfile = "grem";
          browser.profiles.grem = {
            cdpPort = 18800;
            color = "#FF4500";
          };
        };
      };

      # Grem - staging instance for testing configuration changes
      instances.grem-staging = lib.recursiveUpdate baseInstance {
        gatewayPort = 18889; # Different port from default (18789)
        providers.telegram.botTokenFile = nixosConfig.age.secrets.telegram-bot-token-staging.path;
        configOverrides = lib.recursiveUpdate baseConfigOverrides {
          plugins.load.paths = ["/home/chris/.openclaw-grem-staging/extensions"];
          browser.defaultProfile = "grem-staging";
          browser.profiles.grem-staging = {
            cdpPort = 18801;
            color = "#00BFFF";
          };
        };
      };
    };

    # Add OPENAI_BASE_URL for memory-lancedb to use OpenRouter embeddings
    # The nix-openclaw wrapper already handles OPENROUTER_API_KEY from apiKeyFile
    systemd.user.services.openclaw-gateway-grem.Service.Environment = [
      "OPENAI_BASE_URL=https://openrouter.ai/api/v1"
    ];
    systemd.user.services.openclaw-gateway-grem-staging.Service.Environment = [
      "OPENAI_BASE_URL=https://openrouter.ai/api/v1"
    ];

    # Set up extensions symlinks for grem instances
    home.activation.openclaw-grem-extensions = hmLib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p $HOME/.openclaw-grem
      if [ ! -L $HOME/.openclaw-grem/extensions ]; then
        ln -sf $HOME/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions $HOME/.openclaw-grem/extensions
      fi
      mkdir -p $HOME/.openclaw-grem-staging
      if [ ! -L $HOME/.openclaw-grem-staging/extensions ]; then
        ln -sf $HOME/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions $HOME/.openclaw-grem-staging/extensions
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
    dotfiles.opencode.openrouterApiKeyFile = nixosConfig.age.secrets.openrouter-api-key.path;
    programs.starship.enable = false;
  };
}
