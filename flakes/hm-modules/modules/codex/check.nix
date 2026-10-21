{
  pkgs,
  home-manager,
}: let
  mkConfig = extra:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ./default.nix
        {
          home.username = "test";
          home.homeDirectory = "/tmp/codex-test";
          home.stateVersion = "26.05";
          dotfiles.codex.enable = true;
          programs.opencode.enable = true;
          programs.opencode.package = null;
          dotfiles.agentSkills.directory-fixture = {
            source = ../../tests/agent-skills/directory-skill;
            targets = ["opencode" "codex"];
            patches = [../../tests/agent-skills/description.patch];
            extraText = "Shared fixture guidance.";
          };
          dotfiles.agentSkills.opencode-only.source = ../../tests/agent-skills/directory-skill;
          dotfiles.agentSkills.teach.targets = ["opencode"];
          dotfiles.agentSkills.project-map.enable = false;
        }
        extra
      ];
    };
  both = (mkConfig {}).config;
  codexOnly = (mkConfig {programs.opencode.enable = pkgs.lib.mkForce false;}).config;
  codexWithTeach =
    (mkConfig {
      programs.opencode.enable = pkgs.lib.mkForce false;
      dotfiles.agentSkills.teach.targets = ["codex"];
    }).config;
  disabled = (mkConfig {dotfiles.codex.enable = pkgs.lib.mkForce false;}).config;
  xdg = (mkConfig {home.preferXdgDirectories = true;}).config;
  activation = pkgs.writeText "codex-test-activation" both.home.activation.mergeCodexSettings.data;
  rendered = both.home.file.".agents/skills/directory-fixture".source;
  how = codexOnly.home.file.".agents/skills/how".source;
  why = codexOnly.home.file.".agents/skills/why".source;
  teach = codexWithTeach.home.file.".agents/skills/teach".source;
  skillsManifest = pkgs.writeText "codex-deployed-skills.json" (builtins.toJSON [
    {
      destination = ".agents/skills/how";
      source = toString how;
    }
    {
      destination = ".agents/skills/why";
      source = toString why;
    }
    {
      destination = ".agents/skills/teach";
      source = toString teach;
    }
  ]);
  valid = config: pkgs.lib.all (assertion: assertion.assertion) config.assertions;
in
  assert valid both && valid codexOnly && valid codexWithTeach && valid disabled && valid xdg;
  assert both.programs.codex.package == null;
  assert !(both.home.file ? ".codex/config.toml");
  assert !(both.home.file ? ".agents/skills/opencode-only");
  assert !(both.home.file ? ".agents/skills/teach");
  assert !(both.home.file ? ".agents/skills/project-map");
  assert codexOnly.home.file ? ".agents/skills/how";
  assert codexOnly.home.file ? ".agents/skills/why";
  assert !(disabled.home.file ? ".agents/skills/how");
  assert !(disabled.home.file ? ".agents/skills/why");
  assert codexWithTeach.home.file ? ".agents/skills/teach";
  assert !codexOnly.home.file.".agents/skills/how".recursive;
  assert !codexOnly.home.file.".agents/skills/why".recursive;
  assert both.xdg.configFile."opencode/skills/directory-fixture".source == rendered;
  assert !both.home.file.".agents/skills/directory-fixture".recursive;
  assert both.xdg.configFile."opencode/skills/directory-fixture".recursive;
  assert codexOnly.home.file ? ".agents/skills/test-curation";
  assert !(codexOnly.xdg.configFile ? "opencode/skills/test-curation");
  assert !(disabled.home.file ? ".agents/skills/test-curation");
  assert xdg.home.sessionVariables.CODEX_HOME == "/tmp/codex-test/.config/codex";
    pkgs.runCommand "codex-module" {
      nativeBuildInputs = [(pkgs.python3.withPackages (p: [p.tomlkit p.pyyaml]))];
    } ''
      bash -n ${activation}
      test -f ${rendered}/references/companion.md
      grep -Fqx 'description: Patched fixture description.' ${rendered}/SKILL.md
      grep -Fqx 'Shared fixture guidance.' ${rendered}/SKILL.md
      grep -Fq 'direnv exec <workdir> <command>' ${both.home.file.".codex/AGENTS.md".source}
      test -f ${how}/references/architectural-critique-rubric.md
      test -f ${why}/references/epistemics.md
      python3 ${../opencode/tests/check-deployed-skills.py} ${skillsManifest}
      mkdir -p audit/skills
      ln -s ${how} audit/skills/how
      ln -s ${why} audit/skills/why
      python3 - audit/skills <<'PY'
      from pathlib import Path
      import re
      import sys

      skills = Path(sys.argv[1])
      errors = []
      forbidden = re.compile(r"subagent-selection|opencode|\bctx\b|Use Glob to|Grep to find", re.I)
      links = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
      for name in ("how", "why"):
          root = skills / name
          for markdown in root.rglob("*.md"):
              content = markdown.read_text()
              if forbidden.search(content):
                  errors.append(f"{name}: OpenCode-specific or subagent-selection directive in {markdown.relative_to(skills)}")
              for match in links.finditer(content):
                  target = match.group(1).strip().split(maxsplit=1)[0].strip("<>")
                  if not target or target.startswith(("#", "/")) or re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                      continue
                  local = target.split("#", 1)[0]
                  if local and not (markdown.parent / local).resolve().is_file():
                      errors.append(f"{name}: broken Markdown link {target!r} in {markdown.relative_to(skills)}")
      if errors:
          raise SystemExit("\n".join(errors))
      PY
      cp ${./merge-settings.py} merge-settings.py
      cp ${./test-merge-settings.py} test-merge-settings.py
      python3 test-merge-settings.py
      touch "$out"
    ''
