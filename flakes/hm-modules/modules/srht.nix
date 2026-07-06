{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.srht;
  system = pkgs.stdenv.hostPlatform.system;
  hasSrhtModule = inputs ? srht && inputs.srht ? homeManagerModules;
  inputPackage =
    if inputs ? srht && inputs.srht ? packages && builtins.hasAttr system inputs.srht.packages
    then inputs.srht.packages.${system}.srht or inputs.srht.packages.${system}.default
    else null;
in {
  imports = lib.optional hasSrhtModule inputs.srht.homeManagerModules.default;

  options.dotfiles.srht = {
    enable = lib.mkEnableOption "srht SourceHut CLI integration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.srht.packages.${pkgs.stdenv.hostPlatform.system}.srht'';
      description = ''
        srht package to install. Defaults to the srht flake input when the host
        provides it. The package ships bash, fish, and zsh completions under
        share/, so adding it to home.packages installs completions for Home
        Manager-managed shells.
      '';
    };

    opencodeSkills = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install srht's bundled agent skills into ~/.config/opencode/skills
          during Home Manager activation.
        '';
      };

      names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["srht-issues" "srht-ci" "srht-setup"];
        description = ''
          Bundled srht skill names to install. The empty default installs every
          bundled skill exposed by `srht skills install`.
        '';
      };

      force = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Pass --force to `srht skills install` so updated bundled skill content
          replaces previous activation output.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || cfg.package != null;
          message = "dotfiles.srht.enable requires dotfiles.srht.package or an inputs.srht flake input.";
        }
        {
          assertion = !cfg.enable || hasSrhtModule;
          message = "dotfiles.srht.enable requires the srht Home Manager module input to be available.";
        }
      ];
    }
    (lib.optionalAttrs hasSrhtModule (lib.mkIf cfg.enable {
      programs.srht = {
        enable = true;
        inherit (cfg) package;
      };

      home.activation.install-srht-opencode-skills = lib.mkIf cfg.opencodeSkills.enable (lib.hm.dag.entryAfter ["linkGeneration"] ''
        skills_dir="$HOME/.config/opencode/skills"
        ${pkgs.coreutils}/bin/mkdir -p "$skills_dir"
        ${lib.escapeShellArg (lib.getExe cfg.package)} skills install \
          --dir "$skills_dir" \
          ${lib.optionalString cfg.opencodeSkills.force "--force"} \
          ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.opencodeSkills.names}
      '');
    }))
  ];
}
