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
  codexPackage = import ./packages/codex.nix {inherit pkgs;};
  zeroclawPackage = inputs.zeroclaw.packages.${pkgs.stdenv.hostPlatform.system}.zeroclaw.overrideAttrs {
    cargoBuildFlags = [
      "-p"
      "zeroclaw"
      "--no-default-features"
      "--features"
      "agent-runtime,channel-telegram,schema-export"
    ];
  };

  memoPackage = inputs.memo.packages.${pkgs.stdenv.hostPlatform.system}.default;
  rdnyPackage = inputs.rdny.packages.${pkgs.stdenv.hostPlatform.system}.rdny;
  ownerWorkspace = "/var/lib/zeroclaw-home/agents/owner/workspace";
  rdnyOwnerWrapper = pkgs.writeShellScriptBin "rdny" ''
    export RDNY_CHROME="${lib.getExe pkgs.ungoogled-chromium}"
    export RDNY_FFMPEG="${lib.getExe pkgs.ffmpeg}"
    export HOME="${ownerWorkspace}"
    export RDNY_STATE_DIR="${ownerWorkspace}/.rdny"
    exec ${lib.getExe rdnyPackage} "$@"
  '';
  codexJobScript = ../../../scripts/michi-codex.py;
  codexInstructions = pkgs.writeText "michi-codex-AGENTS.md" (
    builtins.readFile ../../hm-modules/modules/agent-guidance.md
    + "\n"
    + builtins.readFile ./michi/CODING.md
  );
  codexOwnerWrapper = pkgs.writeShellScriptBin "michi-codex" ''
    export MICHI_CODEX_ROOT="${ownerWorkspace}"
    export MICHI_CODEX_BINARY="${lib.getExe codexPackage}"
    exec ${lib.getExe pkgs.python3} ${codexJobScript} "$@"
  '';
  codexTokenScript = pkgs.writeText "michi-codex-token.py" ''
    import os, pathlib, re, tempfile
    lines = pathlib.Path("${config.age.secrets.zeroclaw-env.path}").read_text().splitlines()
    values = [line.split("=", 1)[1].strip() for line in lines if line.startswith("GH_TOKEN=")]
    token = values[-1].strip("\"'") if values else ""
    if not re.fullmatch(r"[A-Za-z0-9_]+", token):
        raise SystemExit("GH_TOKEN is missing or malformed")
    fd, path = tempfile.mkstemp(prefix=".michi-codex-gh-", dir="/run")
    try:
        os.fchmod(fd, 0o400)
        with os.fdopen(fd, "w") as output:
            output.write("GH_TOKEN=" + token + "\n")
        os.replace(path, "/run/michi-codex-gh.env")
    finally:
        if os.path.exists(path):
            os.unlink(path)
  '';
  publishBrowserNamespace = pkgs.writeShellApplication {
    name = "michi-browser-namespace";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      test "''${MAINPID:-0}" -gt 1
      ln -sfn "/proc/''${MAINPID}/ns/user" /run/zeroclaw-home-browser-userns
    '';
  };
  browserStart = pkgs.writeShellApplication {
    name = "michi-browser-start";
    runtimeInputs = [rdnyOwnerWrapper pkgs.jq];
    text = ''
      rdny cleanup
      rdny start --label michi
      jq -er '.endpoint.broker_pid | select(type == "number" and . > 0)' \
        "${ownerWorkspace}/.rdny/state.json" > /run/michi-browser/broker.pid
    '';
  };
  ownerShellPackages = with pkgs; [
    gh
    jujutsu
    git
    ripgrep
    jq
    curl
    fd
    rdnyOwnerWrapper
    codexOwnerWrapper
  ];

  # Keep the parent path valid in a clean checkout. A missing path literal is
  # rejected during Nix evaluation before pathExists can disable the feature.
  secretsDir = ../../../secrets;
  # Check the source path before adding store context, including --no-build CI.
  zeroclawEnvSecret = secretsDir + "/thorny/zeroclaw-env.age";
  secretExists = builtins.pathExists zeroclawEnvSecret;

  # Kagi search and page extraction use the encrypted environment key.
  kagiEnabled = true;

  # Memory and reactions confined to the current conversation.
  memoryTools = ["memo"];
  searchTools = lib.optional kagiEnabled "web_search_tool";
  allowedTools = memoryTools ++ ["reaction" "image_gen"] ++ searchTools;
  # auto_approve replaces the default list, so name every unprompted tool.
  autoApprove = memoryTools ++ ["reaction" "image_gen"] ++ searchTools;

  # One public personality, inherited by invited agents, with private memory
  # left in each agent's own workspace. These files are the authoring source.
  michiIdentity = extraInstructions: {
    format = "aieos";
    aieos_inline = builtins.toJSON {
      identity.bio = builtins.readFile ./michi/IDENTITY.md;
      linguistics.style = builtins.readFile ./michi/SOUL.md + extraInstructions;
    };
  };
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
  environment.systemPackages = [zeroclawPackage codexPackage codexOwnerWrapper];

  # Chromium needs its own namespaces and JavaScript JIT. Keep those outside
  # the bot unit; rdny clients use its private authenticated Unix broker.
  systemd.tmpfiles.rules = lib.mkIf secretExists [
    "d ${ownerWorkspace} 0700 zeroclaw-home zeroclaw-home -"
    "d ${ownerWorkspace}/.codex 0700 zeroclaw-home zeroclaw-home -"
    "L+ ${ownerWorkspace}/.codex/AGENTS.md - - - - ${codexInstructions}"
    "d ${ownerWorkspace}/.codex-jobs 0700 zeroclaw-home zeroclaw-home -"
    "d ${ownerWorkspace}/.codex-jobs/pending 0700 zeroclaw-home zeroclaw-home -"
  ];
  systemd.services.michi-browser = lib.mkIf secretExists {
    description = "Michi private rdny browser";
    wantedBy = ["zeroclaw-home.service"];
    after = ["network-online.target" "zeroclaw-home.service"];
    bindsTo = ["zeroclaw-home.service"];
    partOf = ["zeroclaw-home.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "forking";
      User = "zeroclaw-home";
      Group = "zeroclaw-home";
      WorkingDirectory = ownerWorkspace;
      RuntimeDirectory = "michi-browser";
      RuntimeDirectoryMode = "0700";
      PIDFile = "/run/michi-browser/broker.pid";
      ExecStart = lib.getExe browserStart;
      ExecStop = "${lib.getExe rdnyOwnerWrapper} stop";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStartSec = "60s";
      TimeoutStopSec = "15s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      UserNamespacePath = "/run/zeroclaw-home-browser-userns";
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      RestrictNamespaces = ["user" "pid" "net" "ipc" "mnt" "uts"];
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      ReadWritePaths = [ownerWorkspace];
    };
  };

  # File requests keep coding work outside the bot's 60-second shell timeout.
  systemd.paths.michi-codex = lib.mkIf secretExists {
    wantedBy = ["multi-user.target"];
    pathConfig = {
      DirectoryNotEmpty = "${ownerWorkspace}/.codex-jobs/pending";
      Unit = "michi-codex-worker.service";
    };
  };
  systemd.services.michi-codex-worker = lib.mkIf secretExists {
    description = "Michi owner Codex jobs";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = ownerShellPackages ++ [codexPackage pkgs.bubblewrap pkgs.nix pkgs.direnv pkgs.nodejs pkgs.python3];
    environment = {
      HOME = ownerWorkspace;
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "zeroclaw-home";
      Group = "zeroclaw-home";
      WorkingDirectory = ownerWorkspace;
      ExecStartPre = "+${lib.getExe pkgs.python3} ${codexTokenScript}";
      ExecStart = "${lib.getExe codexOwnerWrapper} _worker";
      ExecStopPost = "+${pkgs.coreutils}/bin/rm -f /run/michi-codex-gh.env";
      EnvironmentFile = "-/run/michi-codex-gh.env";
      TimeoutStartSec = "infinity";
      TimeoutStopSec = "15s";
      KillMode = "control-group";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateUsers = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      # bwrap mounts a new /proc; outer proc submount locks prevent that.
      # Leave ProcSubset, ProtectKernelTunables, and ProtectKernelLogs unset
      # here. The bot retains all three; this worker has no host capabilities.
      ProtectProc = "invisible";
      RestrictNamespaces = ["user" "pid" "net" "ipc" "mnt" "uts"];
      # Offline patch sandboxes need route sockets to set up their loopback.
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      # Expose only the owner's workspace from the shared bot state tree.
      TemporaryFileSystem = ["/var/lib/zeroclaw-home:ro"];
      BindPaths = [ownerWorkspace];
      ReadWritePaths = [ownerWorkspace];
    };
  };

  # rdny validates process identity through /proc. Sharing only the bot's user
  # namespace permits that check without granting the client namespace creation.
  systemd.services.zeroclaw-home.serviceConfig = lib.mkIf secretExists {
    ExecStartPost = ["+${lib.getExe publishBrowserNamespace}"];
    ExecStopPost = ["+${pkgs.coreutils}/bin/rm -f /run/zeroclaw-home-browser-userns"];
  };

  services.zeroclaw.instances.home = lib.mkIf secretExists {
    package = zeroclawPackage;
    extraPackages = [pkgs.ffmpeg memoPackage] ++ ownerShellPackages;
    environmentFile = config.age.secrets.zeroclaw-env.path;

    settings = {
      # These tables already use the current aliased schema; do not migrate them.
      schema_version = 3;
      # ChatGPT/Codex subscription auth; no api_key. The daemon reads the
      # auth profile from /var/lib/zeroclaw-home. Confirm the served model ID
      # against the Codex catalog after logging in.
      providers.models.openai.codex = {
        model = "gpt-6-luna";
        wire_api = "responses";
        requires_openai_auth = true;
      };

      # Runtime effort is explicit; the Codex adapter otherwise defaults to xhigh.
      runtime.reasoning_effort = "medium";
      providers.models.openai.sol = {
        model = "gpt-6.1-sol";
        wire_api = "responses";
        requires_openai_auth = true;
      };
      providers.models.openai.astra = {
        model = "gpt-6-astra";
        wire_api = "responses";
        requires_openai_auth = true;
      };
      model_routes = [
        {
          hint = "Luna";
          model_provider = "openai.codex";
          model = "gpt-6-luna";
        }
        {
          hint = "Sol";
          model_provider = "openai.sol";
          model = "gpt-6.1-sol";
        }
        {
          hint = "Astra";
          model_provider = "openai.astra";
          model = "gpt-6-astra";
        }
      ];

      providers.transcription.opencode_go.michi = {
        api_key = "$OPENCODE_GO_API_KEY";
        model = "mimo-v2.6-flash";
      };
      transcription.enabled = true;
      media_pipeline = {
        enabled = true;
        describe_images = true;
        transcribe_audio = true;
        summarize_video = true;
      };
      image_gen = {
        enabled = true;
        provider = "openai_codex";
        default_model = "gpt-image-2";
      };

      memo = {
        enabled = true;
        executable = "${memoPackage}/bin/memo";
        wake_lines = 256;
      };

      # Memo owns durable memory. Preserve old SQLite files for rollback.
      memory = {
        backend = "none";
        auto_save = false;
        hygiene_enabled = false;
      };

      agents = {
        owner = {
          model_provider = "openai.codex";
          risk_profile = "owner";
          identity = michiIdentity ("\n" + builtins.readFile ./michi/OWNER_TOOLS.md);
          transcription_provider = "opencode_go.michi";
        };
        guest_template = {
          model_provider = "openai.codex";
          risk_profile = "guests";
          identity = michiIdentity "";
          transcription_provider = "opencode_go.michi";
        };
        group_template = {
          model_provider = "openai.codex";
          risk_profile = "guests";
          identity = michiIdentity "";
          transcription_provider = "opencode_go.michi";
        };
      };

      risk_profiles = {
        owner = {
          # Preserve a full 256-line memo wake, including JSON escaping.
          max_tool_result_chars = 524288;
          allowed_tools = allowedTools ++ ["shell"];
          auto_approve = autoApprove ++ ["shell"];
          require_approval_for_medium_risk = false;
          workspace_only = true;
          shell_env_passthrough = ["GH_TOKEN"];
          allowed_commands = [
            "git"
            "gh"
            "jj"
            "rg"
            "jq"
            "curl"
            "fd"
            "rdny"
            "michi-codex"
            "npm"
            "cargo"
            "ls"
            "cat"
            "grep"
            "find"
            "echo"
            "pwd"
            "wc"
            "head"
            "tail"
            "date"
            "df"
            "du"
            "uname"
            "uptime"
            "hostname"
            "python"
            "python3"
            "pip"
            "node"
            "free"
            "ffmpeg"
            "ffprobe"
          ];
        };
        guests = {
          max_tool_result_chars = 524288;
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
        # Reactions should be chosen for the conversation, not sent on every receipt.
        ack_reactions = false;
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
