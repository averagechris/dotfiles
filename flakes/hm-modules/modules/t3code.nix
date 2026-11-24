{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.t3code;
  telemetryEnvironment = {
    T3CODE_TELEMETRY_ENABLED = "false";
    T3CODE_OTEL_SDK_DISABLED = "true";
  };
  telemetryArgs = lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "${name}=${value}") telemetryEnvironment);
  t3code = inputs.t3-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
  opencode = lib.getExe config.programs.opencode.package;
  opencodeWithOpenrouter = pkgs.writeShellScript "t3code-opencode" ''
    set +x
    if [[ ! -r ${lib.escapeShellArg cfg.openrouterApiKeyFile} ]]; then
      echo "T3 Code OpenCode: OpenRouter key file is unreadable" >&2
      exit 1
    fi
    OPENROUTER_API_KEY="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.openrouterApiKeyFile})"
    if [[ -z "$OPENROUTER_API_KEY" ]]; then
      echo "T3 Code OpenCode: OpenRouter key file is empty" >&2
      exit 1
    fi
    export OPENROUTER_API_KEY
    exec ${opencode} "$@"
  '';
in {
  options.dotfiles.t3code.openrouterApiKeyFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Runtime path to an OpenRouter API key for OpenCode launched by T3 Code.
      The key is read when the OpenCode process starts and is never embedded in
      Nix store settings or the launcher.
    '';
  };

  config = {
    home.sessionVariables = telemetryEnvironment;

    # Finder launches need the flags in each new GUI login session.
    launchd.agents.t3code-telemetry = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments =
          ["/bin/launchctl" "setenv"]
          ++ lib.concatLists (lib.mapAttrsToList (name: value: [name value]) telemetryEnvironment);
        RunAtLoad = true;
      };
    };

    programs.t3code = {
      enable = true;
      package = t3code;
      userSettings.providerInstances.opencode = {
        driver = "opencode";
        enabled = true;
        config = {
          enabled = true;
          binaryPath =
            if cfg.openrouterApiKeyFile == null
            then opencode
            else opencodeWithOpenrouter;
        };
      };
    };

    # The upstream AppImage keeps its desktop entry outside usr/share, which
    # the Nix package copies. Pass the flags when launched outside a login shell.
    xdg.desktopEntries.t3code = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      name = "T3 Code";
      exec = "${pkgs.coreutils}/bin/env ${telemetryArgs} ${lib.getExe t3code} %U";
      icon = "t3code";
      categories = ["Development"];
      mimeType = ["x-scheme-handler/t3code" "x-scheme-handler/t3code-dev"];
      settings.StartupWMClass = "com.t3tools.T3Code";
    };
  };
}
