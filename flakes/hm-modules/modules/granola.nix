{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.granola;
  inputPackage =
    if inputs ? granola-cli && inputs.granola-cli ? packages && builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.granola-cli.packages
    then inputs.granola-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
    else null;
  granolaCompletions = pkgs.runCommand "granola-completions" {} ''
    install -dm755 \
      $out/share/bash-completion/completions \
      $out/share/fish/vendor_completions.d \
      $out/share/zsh/site-functions

    ${lib.getExe cfg.package} completions bash > $out/share/bash-completion/completions/granola
    ${lib.getExe cfg.package} completions fish > $out/share/fish/vendor_completions.d/granola.fish
    ${lib.getExe cfg.package} completions zsh > $out/share/zsh/site-functions/_granola
  '';
  validateFlag = lib.optionalString cfg.validateTokenOnLogin "--validate";
in {
  options.dotfiles.granola = {
    enable = lib.mkEnableOption "Granola CLI and keyring-backed authentication";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.granola-cli.packages.${pkgs.stdenv.hostPlatform.system}.default'';
      description = ''
        Granola CLI package to install. Defaults to the granola-cli flake input
        when the host provides it.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/granola-token";
      description = ''
        Optional path to an agenix-decrypted Granola API token. When set, Home
        Manager activation seeds the CLI's OS keyring entry on first install by
        running `granola auth login --key-stdin` if auth is not already
        configured. The token is never written to shell startup files.
      '';
    };

    validateTokenOnLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Validate the API token with Granola before saving it to the keyring
        during first-time activation.
      '';
    };

    completions.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install generated Granola shell completions in the standard Home Manager
        profile completion directories for enabled shells.
      '';
    };

    sync = {
      enable = lib.mkEnableOption "hourly Granola note cache sync launchd agent";

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3600;
        description = ''
          Number of seconds between background `granola sync` runs. On macOS,
          launchd does not wake a sleeping laptop to run the job.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "dotfiles.granola.enable requires dotfiles.granola.package or an inputs.granola-cli flake input.";
      }
      {
        assertion = !cfg.sync.enable || pkgs.stdenv.isDarwin;
        message = "dotfiles.granola.sync.enable is currently supported only on Darwin via launchd.";
      }
    ];

    home.packages = [cfg.package] ++ lib.optional cfg.completions.enable granolaCompletions;

    launchd.agents.granola-sync = lib.mkIf (cfg.sync.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe cfg.package)
          "sync"
          "--since"
          "12h"
          "--all"
          "--include-transcripts"
          "--quiet"
        ];
        StartInterval = cfg.sync.intervalSeconds;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/granola-sync.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/granola-sync.log";
      };
    };

    home.activation.granola-auth = lib.mkIf (cfg.tokenFile != null) (lib.hm.dag.entryAfter ["writeBoundary" "installPackages"] ''
      token_file=${lib.escapeShellArg cfg.tokenFile}
      granola=${lib.escapeShellArg (lib.getExe cfg.package)}

      if [[ -r "$token_file" ]]; then
        if ! "$granola" auth status --output json --compact 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q '"configured":true'; then
          "$granola" auth login --key-stdin ${validateFlag} --quiet < "$token_file"
        fi
      else
        echo "granola-auth: token file is not readable: $token_file" >&2
      fi
    '');
  };
}
