# One Telegram bot with an owner agent, isolated invited private chats, and
# isolated approved groups. Memberships live in service state across rebuilds.
# See docs/zeroclaw.md. The encrypted environment file contains BOT_TOKEN
# and TG_OWNER_ID, keeping the deployment reproducible without public IDs.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  zeroclawPackage = inputs.zeroclaw.packages.${pkgs.stdenv.hostPlatform.system}.zeroclaw.overrideAttrs {
    cargoBuildFlags = [
      "-p"
      "zeroclaw"
      "--no-default-features"
      "--features"
      "agent-runtime,channel-telegram,schema-export"
    ];
  };

  # Keep the parent path valid in a clean checkout. A missing path literal is
  # rejected during Nix evaluation before pathExists can disable the feature.
  secretsDir = ../../../secrets;
  # Check the source path before adding store context, including --no-build CI.
  zeroclawEnvSecret = secretsDir + "/thorny/zeroclaw-env.age";
  secretExists = builtins.pathExists zeroclawEnvSecret;

  # Stage 2 of the runbook: flip after the stage 1 isolation checks pass.
  kagiEnabled = false;

  # Stage 1 grants the built-in memory tools only.
  memoryTools = ["memory_recall" "memory_store" "memory_forget"];
  searchTools = lib.optional kagiEnabled "web_search_tool";
  allowedTools = memoryTools ++ searchTools;
  # auto_approve replaces the default list, so name every unprompted tool.
  autoApprove = ["memory_recall" "memory_store"] ++ searchTools;
in {
  imports = [inputs.zeroclaw.nixosModules.default];

  age.secrets = lib.mkIf secretExists {
    zeroclaw-env = {
      file = zeroclawEnvSecret;
      # Read by systemd as root via EnvironmentFile.
      mode = "0400";
    };
  };

  warnings =
    lib.optional (!secretExists)
    "ZeroClaw is staged off: provision secrets/thorny/zeroclaw-env.age before deploying Thorny.";

  # `zeroclaw auth login` for the Codex subscription must run as the service
  # user with the same build as the unit (runbook step 5).
  environment.systemPackages = [zeroclawPackage];

  services.zeroclaw.instances.home = lib.mkIf secretExists {
    package = zeroclawPackage;
    environmentFile = config.age.secrets.zeroclaw-env.path;

    settings = {
      # ChatGPT/Codex subscription auth; no api_key. The daemon reads the
      # auth profile from /var/lib/zeroclaw-home. Confirm the served model ID
      # against the Codex catalog after logging in.
      providers.models.openai.codex = {
        model = "gpt-5.4";
        wire_api = "responses";
        requires_openai_auth = true;
      };

      agents = {
        owner = {
          model_provider = "openai.codex";
          risk_profile = "owner";
        };
        guest_template = {
          model_provider = "openai.codex";
          risk_profile = "guests";
        };
        group_template = {
          model_provider = "openai.codex";
          risk_profile = "guests";
        };
      };

      risk_profiles = {
        owner = {
          allowed_tools = allowedTools;
          auto_approve = autoApprove;
        };
        guests = {
          allowed_tools = allowedTools;
          excluded_tools = ["shell"];
          auto_approve = autoApprove;
        };
      };

      # Owner admission is declarative; guests and groups use the durable registry.
      # admin_for_agent_scope stays false: no /model --agent from Telegram.
      peer_groups.telegram_home = {
        channel = "telegram.home";
        external_peers = ["$TG_OWNER_ID"];
      };

      channels.telegram.home = {
        enabled = true;
        bot_token = "$BOT_TOKEN";
        # One shared group session; DMs are unaffected.
        per_user_session = false;
        stream_mode = "partial";
        # The owner retains a fixed agent. Invites create isolated identities
        # from the templates without writing them into this Nix-owned TOML.
        routes."$TG_OWNER_ID" = "owner";
        invitations = {
          owner_id = "$TG_OWNER_ID";
          guest_agent = "guest_template";
          group_agent = "group_template";
        };
      };

      web_search = lib.mkIf kagiEnabled {
        enabled = true;
        search_provider = "kagi";
        kagi_api_key = "$KAGI_API_KEY";
      };
    };
  };
}
