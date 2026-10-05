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
  gitCredentialEnvironment = {
    GIT_CONFIG_COUNT = "1";
    GIT_CONFIG_KEY_0 = "credential.https://github.com.helper";
    GIT_CONFIG_VALUE_0 = "!${lib.getExe pkgs.gh} auth git-credential";
  };
  rdnyOwnerWrapper = pkgs.writeShellScriptBin "rdny" ''
    export RDNY_CHROME="${lib.getExe pkgs.ungoogled-chromium}"
    export RDNY_FFMPEG="${lib.getExe pkgs.ffmpeg}"
    export HOME="${ownerWorkspace}"
    export RDNY_STATE_DIR="${ownerWorkspace}/.rdny"
    exec ${lib.getExe rdnyPackage} "$@"
  '';
  codexJobScript = ../../../scripts/michi-codex.py;
  codexNotify = pkgs.writeShellScriptBin "michi-codex-notify" ''
    export MICHI_CODEX_ROOT="${ownerWorkspace}"
    exec ${lib.getExe pkgs.python3} ${../../../scripts/michi-codex-notify.py}
  '';
  codexNotifyTokenScript = pkgs.writeText "michi-codex-notify-token.py" ''
    import os, pathlib, re, sys, tempfile
    values = {}
    for line in pathlib.Path("${config.age.secrets.zeroclaw-env.path}").read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator and key in {"BOT_TOKEN", "TG_OWNER_ID"}:
            values[key] = value.strip().strip("\"'")
    if not re.fullmatch(r"[0-9]+:[A-Za-z0-9_-]+", values.get("BOT_TOKEN", "")):
        raise SystemExit("BOT_TOKEN is missing or malformed")
    if not re.fullmatch(r"[1-9][0-9]*", values.get("TG_OWNER_ID", "")):
        raise SystemExit("TG_OWNER_ID is missing or malformed")
    fd, path = tempfile.mkstemp(prefix=".michi-codex-notify-", dir="/run")
    try:
        os.fchmod(fd, 0o400)
        with os.fdopen(fd, "w") as output:
            for key, value in values.items():
                output.write(key + "=" + value + "\n")
        os.replace(path, sys.argv[1])
    finally:
        if os.path.exists(path):
            os.unlink(path)
  '';
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
  codexOwnerCli = pkgs.writeShellScriptBin "codex" ''
    export HOME="${ownerWorkspace}"
    export CODEX_HOME="${ownerWorkspace}/.codex"
    export GIT_CONFIG_COUNT="${gitCredentialEnvironment.GIT_CONFIG_COUNT}"
    export GIT_CONFIG_KEY_0="${gitCredentialEnvironment.GIT_CONFIG_KEY_0}"
    export GIT_CONFIG_VALUE_0="${gitCredentialEnvironment.GIT_CONFIG_VALUE_0}"
    exec ${lib.getExe codexPackage} \
      -c 'cli_auth_credentials_store="file"' \
      -c 'model="gpt-6.1-sol"' -c 'model_reasoning_effort="low"' \
      -c 'allow_login_shell=false' "$@"
  '';
  codexSessionPython = pkgs.python3.withPackages (ps: [ps.websocket-client]);
  codexSessions = pkgs.writeShellScriptBin "michi-codex-sessions" ''
    export MICHI_CODEX_ROOT="${ownerWorkspace}"
    exec ${lib.getExe codexSessionPython} ${../../../scripts/michi-codex-sessions.py} "$@"
  '';
  codexTokenScript = pkgs.writeText "michi-codex-token.py" ''
    import os, pathlib, re, sys, tempfile
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
        os.replace(path, sys.argv[1])
    finally:
        if os.path.exists(path):
            os.unlink(path)
  '';
  codexSandbox = {
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
    # here. The bot retains all three; these Codex services have no host capabilities.
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
    codexOwnerCli
    codexSessions
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
    environment =
      gitCredentialEnvironment
      // {
        HOME = ownerWorkspace;
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    serviceConfig =
      codexSandbox
      // {
        Type = "oneshot";
        User = "zeroclaw-home";
        Group = "zeroclaw-home";
        WorkingDirectory = ownerWorkspace;
        ExecStartPre = "+${lib.getExe pkgs.python3} ${codexTokenScript} /run/michi-codex-gh.env";
        ExecStart = "${lib.getExe codexOwnerWrapper} _worker";
        ExecStopPost = "+${pkgs.coreutils}/bin/rm -f /run/michi-codex-gh.env";
        EnvironmentFile = "-/run/michi-codex-gh.env";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = "15s";
        KillMode = "control-group";
      };
  };

  # Delivery has its own credentials and lifetime. It never starts Codex.
  systemd.timers.michi-codex-notify = lib.mkIf secretExists {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitInactiveSec = "30s";
      AccuracySec = "5s";
      Unit = "michi-codex-notify.service";
    };
  };
  systemd.services.michi-codex-notify = lib.mkIf secretExists {
    description = "Deliver Michi owner Codex follow-ups";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    serviceConfig =
      codexSandbox
      // {
        Type = "oneshot";
        User = "zeroclaw-home";
        Group = "zeroclaw-home";
        WorkingDirectory = ownerWorkspace;
        ExecStartPre = "+${lib.getExe pkgs.python3} ${codexNotifyTokenScript} /run/michi-codex-notify.env";
        ExecStart = lib.getExe codexNotify;
        ExecStopPost = "+${pkgs.coreutils}/bin/rm -f /run/michi-codex-notify.env";
        EnvironmentFile = "-/run/michi-codex-notify.env";
        RestrictNamespaces = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        TimeoutStartSec = "5min";
      };
  };

  systemd.services.michi-codex-remote = lib.mkIf secretExists {
    description = "Thorny Codex phone host";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    unitConfig.ConditionPathExists = "${ownerWorkspace}/.codex/auth.json";
    path = ownerShellPackages ++ [codexPackage pkgs.bubblewrap pkgs.nix pkgs.direnv pkgs.nodejs pkgs.python3];
    environment =
      gitCredentialEnvironment
      // {
        HOME = ownerWorkspace;
        CODEX_HOME = "${ownerWorkspace}/.codex";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    serviceConfig =
      codexSandbox
      // {
        Type = "simple";
        User = "zeroclaw-home";
        Group = "zeroclaw-home";
        WorkingDirectory = ownerWorkspace;
        ExecStartPre = "+${lib.getExe pkgs.python3} ${codexTokenScript} /run/michi-codex-remote-gh.env";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe codexPackage)
          "-c"
          ''cli_auth_credentials_store="file"''
          "-c"
          ''model="gpt-6.1-sol"''
          "-c"
          ''model_reasoning_effort="low"''
          "-c"
          ''approval_policy="never"''
          "-c"
          ''sandbox_mode="workspace-write"''
          "-c"
          "allow_login_shell=false"
          "-c"
          "sandbox_workspace_write.network_access=true"
          "-c"
          "shell_environment_policy.ignore_default_excludes=true"
          "-c"
          ''agents.default_subagent_model="gpt-6-luna"''
          "-c"
          ''agents.default_subagent_reasoning_effort="medium"''
          "app-server"
          "--remote-control"
          "--listen"
          "unix://${ownerWorkspace}/.codex/michi-app-server.sock"
        ];
        ExecStopPost = "+${pkgs.coreutils}/bin/rm -f /run/michi-codex-remote-gh.env";
        EnvironmentFile = "-/run/michi-codex-remote-gh.env";
        # Codex's socket alias targets /tmp; share only this private runtime
        # directory with owner clients, keeping the resolved Unix path short.
        RuntimeDirectory = "michi-codex-remote";
        RuntimeDirectoryMode = "0700";
        BindPaths = codexSandbox.BindPaths ++ ["/run/michi-codex-remote:/tmp"];
        Restart = "on-failure";
        RestartSec = "10s";
        KillSignal = "SIGINT";
        KillMode = "control-group";
        TimeoutStopSec = "30s";
      };
  };

  # rdny validates process identity through /proc. Sharing only the bot's user
  # namespace permits that check without granting the client namespace creation.
  systemd.services.zeroclaw-home.serviceConfig = lib.mkIf secretExists {
    ExecStartPost = ["+${lib.getExe publishBrowserNamespace}"];
    ExecStopPost = ["+${pkgs.coreutils}/bin/rm -f /run/zeroclaw-home-browser-userns"];
  };
  systemd.services.zeroclaw-home.environment = lib.mkIf secretExists gitCredentialEnvironment;

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
          shell_env_passthrough = ["GH_TOKEN" "TG_OWNER_ID"] ++ builtins.attrNames gitCredentialEnvironment;
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
            "codex"
            "michi-codex-sessions"
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
