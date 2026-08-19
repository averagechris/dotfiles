{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.agentSkills;
  bundles = config.dotfiles.agentSkillBundles;
  agentSkillsLib = import ./agent-skills-lib.nix {inherit lib;};
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
        description = "Upstream SKILL.md file or complete skill directory registered by the owning CLI module.";
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
      mkdir "$out"
      if [ -d ${skill.source} ]; then
        cp -R ${skill.source}/. "$out/"
      else
        cp ${skill.source} "$out/SKILL.md"
      fi
      if [ ! -f "$out/SKILL.md" ]; then
        echo "dotfiles.agentSkills.${name}.source directory must contain SKILL.md" >&2
        exit 1
      fi
      chmod u+w "$out/SKILL.md"
      ${lib.concatMapStringsSep "\n" (patchFile: ''
          patch --batch --fuzz=0 "$out/SKILL.md" < ${patchFile}
        '')
        skill.patches}
      ${lib.optionalString (skill.extraText != "") ''
        printf '\n' >> "$out/SKILL.md"
        cat ${extraText} >> "$out/SKILL.md"
      ''}
    '';
  skillFiles = lib.mapAttrs' (name: skill:
    lib.nameValuePair "opencode/skills/${name}" {
      source = renderSkill name skill;
      recursive = true;
    })
  enabledSkills;
  bundleAssertions = lib.concatMap (bundleName: let
    bundle = bundles.${bundleName};
    audit = agentSkillsLib.auditBundle bundle;
    renderNames = names:
      if names == []
      then "none"
      else lib.concatStringsSep ", " names;
  in [
    {
      assertion = bundle.sourceDirectory != null;
      message = "dotfiles.agentSkillBundles.${bundleName}.sourceDirectory is required.";
    }
    {
      assertion = builtins.length bundle.expectedNames == builtins.length (lib.unique bundle.expectedNames);
      message = "dotfiles.agentSkillBundles.${bundleName}.expectedNames must not contain duplicates.";
    }
    {
      assertion = audit.matches;
      message = ''
        ${bundleName} bundled skills changed; added: ${renderNames audit.added}; removed: ${renderNames audit.removed}. Review each change, update expectedNames, then keep, patch, or disable every registered skill explicitly.
      '';
    }
    {
      assertion = lib.all (name: builtins.hasAttr name cfg) audit.expected;
      message = "dotfiles.agentSkillBundles.${bundleName}.expectedNames contains a skill without a dotfiles.agentSkills registration.";
    }
  ]) (builtins.attrNames bundles);
in {
  options.dotfiles.agentSkills = lib.mkOption {
    type = lib.types.attrsOf skillType;
    default = {};
    description = ''
      Declarative Agent Skills registered by CLI modules. Every registered skill
      is enabled by default and can be patched, extended, or disabled per host.
    '';
  };

  options.dotfiles.agentSkillBundles = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        sourceDirectory = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Directory whose bundled skills are audited against expectedNames.";
        };
        layout = lib.mkOption {
          type = lib.types.enum ["directories" "flat-markdown"];
          default = "directories";
          description = "Whether skills are `<name>/SKILL.md` directories or flat `<name>.md` files.";
        };
        expectedNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Audited bundled skill names expected from this package source.";
        };
      };
    });
    default = {};
    description = "Audited CLI skill bundles that fail evaluation when upstream names drift.";
  };

  config = lib.mkMerge [
    {assertions = bundleAssertions;}
    (lib.mkIf config.programs.opencode.enable {
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
        cfg
        ++ lib.mapAttrsToList (name: skill: let
          sourceIsLiteralDirectory =
            skill.source
            != null
            && builtins.typeOf skill.source == "path"
            && builtins.readFileType skill.source == "directory";
        in {
          assertion = !skill.enable || !sourceIsLiteralDirectory || builtins.pathExists (skill.source + "/SKILL.md");
          message = "dotfiles.agentSkills.${name}.source directory must contain SKILL.md.";
        })
        cfg;

      xdg.configFile = skillFiles;
    })
  ];
}
