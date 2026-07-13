{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.agentSkills;
  skillType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Link this Agent Skill into OpenCode's skill directory.";
      };

      source = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Upstream SKILL.md source registered by the owning CLI module.";
      };

      patches = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = ''
          Ordered strict patches applied to the upstream SKILL.md. Patches use
          fuzz zero and fail the build when upstream content drifts.
        '';
      };

      extraText = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additive Markdown appended after patches are applied.";
      };
    };
  };
  enabledSkills = lib.filterAttrs (_: skill: skill.enable && skill.source != null) cfg;
  renderSkill = name: skill: let
    extraText = pkgs.writeText "${name}-skill-extra.md" skill.extraText;
  in
    pkgs.runCommand "${name}-skill" {
      nativeBuildInputs = [pkgs.patch];
    } ''
      cp ${skill.source} "$out"
      chmod u+w "$out"
      ${lib.concatMapStringsSep "\n" (patchFile: ''
          patch --batch --fuzz=0 "$out" < ${patchFile}
        '')
        skill.patches}
      ${lib.optionalString (skill.extraText != "") ''
        printf '\n' >> "$out"
        cat ${extraText} >> "$out"
      ''}
    '';
  skillFiles = lib.mapAttrs' (name: skill:
    lib.nameValuePair "opencode/skills/${name}/SKILL.md" {
      source = renderSkill name skill;
    })
  enabledSkills;
in {
  options.dotfiles.agentSkills = lib.mkOption {
    type = lib.types.attrsOf skillType;
    default = {};
    description = ''
      Declarative Agent Skills registered by CLI modules. Every registered skill
      is enabled by default and can be patched, extended, or disabled per host.
    '';
  };

  config = lib.mkIf config.programs.opencode.enable {
    assertions =
      lib.mapAttrsToList (name: skill: {
        assertion = builtins.match "^[a-z0-9]+(-[a-z0-9]+)*$" name != null;
        message = "dotfiles.agentSkills skill names must be lowercase kebab-case: ${name}";
      })
      cfg
      ++ lib.mapAttrsToList (name: skill: {
        assertion = !skill.enable || skill.source != null;
        message = "dotfiles.agentSkills.${name}.source is required while the skill is enabled.";
      })
      cfg;

    xdg.configFile = skillFiles;
  };
}
