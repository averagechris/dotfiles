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
  disabled = (mkConfig {dotfiles.codex.enable = pkgs.lib.mkForce false;}).config;
  xdg = (mkConfig {home.preferXdgDirectories = true;}).config;
  activation = pkgs.writeText "codex-test-activation" both.home.activation.mergeCodexSettings.data;
  rendered = both.home.file.".agents/skills/directory-fixture".source;
  valid = config: pkgs.lib.all (assertion: assertion.assertion) config.assertions;
in
  assert valid both && valid codexOnly && valid disabled && valid xdg;
  assert both.programs.codex.package == null;
  assert !(both.home.file ? ".codex/config.toml");
  assert !(both.home.file ? ".agents/skills/opencode-only");
  assert !(both.home.file ? ".agents/skills/teach");
  assert !(both.home.file ? ".agents/skills/project-map");
  assert both.xdg.configFile."opencode/skills/directory-fixture".source == rendered;
  assert codexOnly.home.file ? ".agents/skills/test-curation";
  assert !(codexOnly.xdg.configFile ? "opencode/skills/test-curation");
  assert !(disabled.home.file ? ".agents/skills/test-curation");
  assert xdg.home.sessionVariables.CODEX_HOME == "/tmp/codex-test/.config/codex";
    pkgs.runCommand "codex-module" {
      nativeBuildInputs = [(pkgs.python3.withPackages (p: [p.tomlkit]))];
    } ''
        bash -n ${activation}
      test -f ${rendered}/references/companion.md
        grep -Fqx 'description: Patched fixture description.' ${rendered}/SKILL.md
        grep -Fqx 'Shared fixture guidance.' ${rendered}/SKILL.md
        grep -Fq 'Delegate independent' ${both.home.file.".codex/AGENTS.md".source}
        cp ${./merge-settings.py} merge-settings.py
        cp ${./test-merge-settings.py} test-merge-settings.py
        python3 test-merge-settings.py
        touch "$out"
    ''
