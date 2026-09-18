{
  description = "Home-manager modules for dotfiles";

  inputs = {
    base-lib.url = "path:../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    flake-utils.follows = "base-lib/flake-utils";
    home-manager.follows = "base-lib/home-manager";
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.systems.follows = "flake-utils/systems";
    };
    linear-cli = {
      url = "sourcehut:~averagechris/linear-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    srht = {
      url = "sourcehut:~averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gander = {
      url = "sourcehut:~averagechris/gander";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sideshow = {
      url = "sourcehut:~averagechris/sideshow";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rdny = {
      url = "sourcehut:~averagechris/rdny";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    nitter-link = {
      url = "git+https://git.sr.ht/~averagechris/nitter-link?ref=refs/tags/v0.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    opencode.follows = "base-lib/opencode";
  };

  outputs = inputs @ {
    nixpkgs,
    flake-utils,
    home-manager,
    base-lib,
    ...
  }:
    {
      homeManagerModules = {
        default = ./modules/default.nix;
        agentSkills = ./modules/agent-skills.nix;
        shell = ./modules/shell.nix;
        helix = ./modules/helix/default.nix;
        opencode = ./modules/opencode/default.nix;
        pi = ./modules/pi.nix;
        ctx = ./modules/ctx.nix;
        gander = ./modules/gander.nix;
        granola = ./modules/granola.nix;
        rdny = ./modules/rdny.nix;
        sideshow = ./modules/sideshow.nix;
        linearCli = ./modules/linear-cli;
        srht = ./modules/srht.nix;
        nitterLink = ./modules/nitter-link.nix;
        ghostty-fix = ./modules/ghostty-fix.nix;

        meganz = ./modules/meganz.nix;
        gui = {
          default = ./modules/gui/default.nix;
          alacritty = ./modules/gui/alacritty.nix;
          cosmicPortalWorkarounds = ./modules/gui/cosmic-portal-workarounds.nix;
          firefox = ./modules/gui/firefox.nix;
          kitty = ./modules/gui/kitty.nix;
          zed = ./modules/gui/zed.nix;
          zoom = ./modules/gui/zoom.nix;
          linux_desktop = ./modules/gui/linux_desktop.nix;
          hyprland = ./modules/gui/hyprland/default.nix;
          wezterm = ./modules/gui/wezterm/default.nix;
          ghostty = ./modules/gui/ghostty/default.nix;
        };
        shellModules = {
          calibre-utils = ./modules/shell-modules/calibre-utils.nix;
          fzf = ./modules/shell-modules/fzf.nix;
          lazygit = ./modules/shell-modules/lazygit.nix;
          less = ./modules/shell-modules/less.nix;
          pipx = ./modules/shell-modules/pipx.nix;
          ranger = ./modules/shell-modules/ranger.nix;
          shell_extras = ./modules/shell-modules/shell_extras.nix;
          yazi = ./modules/shell-modules/yazi.nix;
          zsh = ./modules/shell-modules/zsh.nix;
        };
        git = ./modules/git/default.nix;
        gitui = ./modules/gitui/default.nix;
        helixTerminalTools = ./modules/helix-terminal-tools/default.nix;
        helixYaziIntegration = ./modules/helix-yazi-integration/default.nix;
        jujutsu = ./modules/jujutsu/default.nix;
        neovim = ./modules/neovim/default.nix;
        zellij = ./modules/zellij/default.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (final: prev: let
            inherit (prev.stdenv.hostPlatform) system;
            opencodeInput = inputs.opencode;
            rev = opencodeInput.shortRev or opencodeInput.dirtyShortRev or "dirty";
            node_modules = final.callPackage "${opencodeInput}/nix/node_modules.nix" {inherit rev;};
          in {
            titlecase = base-lib.inputs.titlecase.packages.${system}.default;
            pi-coding-agent = final.callPackage ../base-lib/packages/pi-coding-agent.nix {};
            pi = final.pi-coding-agent;
            helium-bin = final.callPackage ../base-lib/packages/helium-bin.nix {};
            nitter-link-chrome-extension = inputs.nitter-link.packages.${system}.chrome-extension;
            nitter-link-firefox-extension = inputs.nitter-link.packages.${system}.firefox-extension;
            notion-cli = final.callPackage ../base-lib/packages/notion-cli.nix {};
            rose-pine-gtk-modern = final.callPackage ../base-lib/packages/rose-pine-gtk-modern.nix {};
            showboat = final.callPackage ../base-lib/packages/showboat.nix {};
            opencode = final.callPackage "${opencodeInput}/nix/opencode.nix" {
              inherit node_modules;
            };
          })
        ];
      };
      inherit (pkgs.stdenv) isLinux;
      # Provide dotfiles_lib that modules expect (normally provided by base-lib)
      dotfiles_lib = {
        options = with nixpkgs.lib; {
          mkDefaultEnabledOption = description:
            mkOption {
              type = types.bool;
              default = true;
              example = false;
              inherit description;
            };
        };
      };
      opencodePluginRuntime = pkgs.callPackage ./modules/opencode/plugin-runtime {};
    in {
      checks = {
        agent-skills-directory-source = let
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              ./modules/agent-skills.nix
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = pkgs.hello;
                dotfiles.agentSkills.directory-fixture = {
                  source = ./tests/agent-skills/directory-skill;
                  patches = [./tests/agent-skills/description.patch];
                  extraText = "Appended fixture guidance.";
                };
              }
            ];
          };
          rendered = testConfig.config.xdg.configFile."opencode/skills/directory-fixture".source;
        in
          pkgs.runCommand "agent-skills-directory-source" {} ''
            test -f "${rendered}/SKILL.md"
            test -f "${rendered}/references/companion.md"
            grep -Fqx 'description: Patched fixture description.' "${rendered}/SKILL.md"
            grep -Fqx 'Appended fixture guidance.' "${rendered}/SKILL.md"
            grep -Fqx 'Companion content remains unchanged.' "${rendered}/references/companion.md"
            mkdir "$out"
          '';

        sideshow-agent-skills = let
          opencodeAgentToolsStub = {lib, ...}: {
            options.dotfiles.opencode.agentTools = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [];
            };
          };
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {inherit inputs;};
            modules = [
              ./modules/sideshow.nix
              opencodeAgentToolsStub
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = pkgs.hello;
                dotfiles.sideshow = {
                  enable = true;
                  opencode.exposeTool = false;
                };
              }
            ];
          };
          packageWithoutSource = pkgs.runCommand "sideshow-without-source" {} ''
            mkdir -p "$out/bin"
            touch "$out/bin/sideshow-without-source"
            chmod +x "$out/bin/sideshow-without-source"
          '';
          overrideConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {inherit inputs;};
            modules = [
              ./modules/sideshow.nix
              opencodeAgentToolsStub
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = pkgs.hello;
                dotfiles.sideshow = {
                  enable = true;
                  package = packageWithoutSource;
                  opencode.exposeTool = false;
                };
              }
            ];
          };
          renderedDeckAuthor = testConfig.config.xdg.configFile."opencode/skills/sideshow-deck-author".source;
          renderedWorkStory = testConfig.config.xdg.configFile."opencode/skills/sideshow-work-story".source;
        in
          assert pkgs.lib.all (entry: entry.assertion) testConfig.config.assertions;
          assert !(overrideConfig.config.dotfiles.agentSkills ? sideshow-deck-author);
          assert overrideConfig.config.dotfiles.agentSkills ? sideshow-work-story;
            pkgs.runCommand "sideshow-agent-skills" {} ''
              test -f "${renderedDeckAuthor}/SKILL.md"
              test -f "${renderedDeckAuthor}/fragment-patterns.md"
              test -f "${renderedDeckAuthor}/project-artifacts.md"
              test -f "${renderedWorkStory}/SKILL.md"
              mkdir "$out"
            '';

        rose-pine-gtk-modern-layout = let
          theme = pkgs.rose-pine-gtk-modern;
          closure = pkgs.closureInfo {rootPaths = [theme];};
        in
          pkgs.runCommand "rose-pine-gtk-modern-layout" {} ''
            for variant in rose-pine rose-pine-dawn rose-pine-moon; do
              test -f "${theme}/share/themes/$variant/gtk-3.0/gtk.css"
              test -f "${theme}/share/themes/$variant/gtk-3.0/gtk-dark.css"
              test -f "${theme}/share/themes/$variant/gtk-3.0/gtk.gresource"
              test -f "${theme}/share/themes/$variant/gtk-4.0/gtk.css"
              test -f "${theme}/share/themes/$variant/gtk-4.0/gtk-dark.css"

              if test -e "${theme}/share/themes/$variant/gtk-2.0"; then
                echo "GTK 2 theme path found for $variant" >&2
                exit 1
              fi
            done

            # Check the complete runtime closure, not just the package's direct
            # references. Theme-only output must not retain GTK 2 or Murrine.
            if grep -Eiq -- '-(gtk2|gtk\+?-?2|[^/]*murrine)' "${closure}/store-paths"; then
              echo "GTK 2 or Murrine found in Rosé Pine runtime closure:" >&2
              grep -Ei -- '-(gtk2|gtk\+?-?2|[^/]*murrine)' "${closure}/store-paths" >&2
              exit 1
            fi
            touch "$out"
          '';

        rose-pine-gtk-modern-home-manager =
          if isLinux
          then let
            theme = pkgs.rose-pine-gtk-modern;
            themedConfig = home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./modules/gui/theming/default.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/tmp/test-home";
                  home.stateVersion = "26.05";
                  dotfiles.theming.enable = true;
                }
              ];
            };
          in
            assert themedConfig.config.gtk.gtk2.enable == false;
            assert themedConfig.config.gtk.gtk3.theme.name == "rose-pine-moon";
            assert themedConfig.config.gtk.gtk4.theme.name == "rose-pine-moon";
            assert themedConfig.config.gtk.gtk3.theme.package.outPath == theme.outPath;
            assert themedConfig.config.gtk.gtk4.theme.package.outPath == theme.outPath;
              pkgs.runCommand "rose-pine-gtk-modern-home-manager" {} ''
                touch "$out"
              ''
          else
            pkgs.runCommand "rose-pine-gtk-modern-home-manager-skipped" {} ''
              touch "$out"
            '';

        # Test that modules can be imported and evaluated with home-manager
        # This forces evaluation of the home-manager configuration, catching any
        # module syntax errors, missing imports, or type mismatches.
        # Only runs on Linux since many GUI modules (waybar, etc.) are Linux-only.
        modules-eval =
          if isLinux
          then let
            testConfig = home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit dotfiles_lib inputs system;
                sshKeys = inputs.base-lib.sshKeys;
                # Provide empty secrets for modules that optionally use agenix secrets
                secrets = {};
              };
              modules = [
                ./modules/default.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/tmp/test-home";
                  home.stateVersion = "26.05";
                }
              ];
            };
          in
            # Force evaluation of the activation package to catch errors
            pkgs.runCommand "hm-modules-eval-test" {} ''
              # Reference the activation package to force evaluation
              echo "Testing home-manager module evaluation..."
              echo "Activation package: ${testConfig.activationPackage}"
              mkdir -p $out
              touch $out/success
            ''
          else
            # On non-Linux systems, just verify the flake structure is valid
            pkgs.runCommand "hm-modules-structure-test" {} ''
              echo "Home-manager modules structure check passed (full eval skipped on non-Linux)"
              mkdir -p $out
              touch $out/success
            '';

        opencode-agent-routing = let
          inherit (pkgs) lib;
          settings = import ./modules/opencode/settings.nix {
            inherit lib pkgs;
            managedJjWorkspaceExternalDirectories = {};
          };
          agents = import ./modules/opencode/primary-agents.nix {
            agentSelectionPolicy = builtins.readFile ./modules/opencode/agent-selection-policy.md;
            agentSelectionTable = builtins.readFile ./modules/opencode/agent-selection-table.md;
            runtimeNote = "test runtime";
          };
          agentSelectionPolicy = builtins.readFile ./modules/opencode/agent-selection-policy.md;
          buildPrompt = agents.build;
          orchestratorPrompt = agents.orchestrator;
          minionPrompt = agents.minion;
          delegatedPrompts = with agents; [build minion tiny luna wise];
          codingPrompts = delegatedPrompts ++ [orchestratorPrompt];
          blockAfter = marker: terminator: prompt:
            builtins.head (lib.splitString terminator (builtins.elemAt (lib.splitString marker prompt) 1));
          permissions = blockAfter "permissions:\n" "\n---";
          taskPermissions = permissions;
          bashPermissions = blockAfter "  # Rules are evaluated" "\n  - action: skill";
          buildBashPermissions = bashPermissions buildPrompt;
          permissionRules = lib.filter (rule: rule != null) (
            map (chunk: let
              lines = lib.splitString "\n" chunk;
              resource = builtins.match ''[ ]*resource: "([^"]+)"'' (builtins.elemAt lines 0);
              effect = builtins.match ''[ ]*effect: (allow|ask|deny)'' (builtins.elemAt lines 1);
            in
              if resource == null || effect == null
              then null
              else {
                pattern = builtins.elemAt resource 0;
                action = builtins.elemAt effect 0;
              }) (lib.tail (lib.splitString "- action: shell\n" buildBashPermissions))
          );
          globMatches = pattern: command: let
            regex = lib.replaceStrings ["\\*" "\\?"] [".*" "."] (lib.escapeRegex pattern);
          in
            builtins.match regex command != null;
          permissionFor = command:
            lib.foldl' (
              action: rule:
                if globMatches rule.pattern command
                then rule.action
                else action
            )
            null
            permissionRules;
          deletionCases = [
            {
              command = "rm -rf build";
              expected = "allow";
            }
            {
              command = "rm -rf /tmp/cache";
              expected = "allow";
            }
            {
              command = "rm -rf /var/log/example";
              expected = "allow";
            }
            {
              command = "rm -rf .";
              expected = "deny";
            }
            {
              command = "rm -rf ../child";
              expected = "deny";
            }
            {
              command = "rm -rf /";
              expected = "deny";
            }
            {
              command = "rm -rf //";
              expected = "deny";
            }
            {
              command = "rm -rf ///";
              expected = "deny";
            }
            {
              command = "rm -rf .//";
              expected = "deny";
            }
            {
              command = "rm -rf ~";
              expected = "deny";
            }
            {
              command = "rm -rf ~/cache";
              expected = "deny";
            }
            {
              command = "rm -rf $HOME/Library";
              expected = "deny";
            }
            {
              command = "rm -rf /Users/chris/Downloads";
              expected = "deny";
            }
            {
              command = "rm -rf /home/chris/Downloads";
              expected = "deny";
            }
            {
              command = "rm -rf cache /Users/chris";
              expected = "deny";
            }
            {
              command = "rm -rf cache ///";
              expected = "deny";
            }
            {
              command = "rm -rf cache .//";
              expected = "deny";
            }
            {
              command = "rm -fr cache $HOME/.cache";
              expected = "deny";
            }
            {
              command = "rm -r cache /home/chris/";
              expected = "deny";
            }
            {
              command = "ssh example.invalid";
              expected = "allow";
            }
            {
              command = "chmod 600 file";
              expected = "allow";
            }
            {
              command = "kubectl delete pod example";
              expected = "allow";
            }
            {
              command = "jj push";
              expected = "allow";
            }
          ];
          nestedDelegationPolicy = blockAfter "## Nested delegation\n\n" "\n## Review routing" agentSelectionPolicy;
          jjSkillRouting = blockAfter "## Jujutsu skill routing\n\n" "\n\n    Do not copy command manuals" orchestratorPrompt;
          frontmatter = blockAfter "---\n" "\n---";
          expectedAgentModels = {
            tiny = "openrouter/openai/gpt-5.6-luna#low";
            luna = "openrouter/openai/gpt-5.6-luna#high";
            minion = "openrouter/openai/gpt-5.6-sol#low";
            wise = "openrouter/anthropic/claude-fable-5.1#high";
          };
          unpinnedAgentPrompts = with agents; [build orchestrator plan];
        in
          assert settings.default_agent == "orchestrator";
          assert settings.experimental.subagent_depth == 2;
          assert settings.agents.explore.model == "openrouter/openai/gpt-5.6-luna#medium";
          assert settings.compaction
          == {
            auto = true;
            buffer = 20000;
            keep.tokens = 15000;
          };
          assert settings.warming == false;
          assert let
            models = settings.providers.openrouter.models;
            expected = [
              "~openai/gpt-sol-latest"
              "~openai/gpt-astra-latest"
              "openai/gpt-5.6-sol"
              "openai/gpt-5.6-luna"
              "anthropic/claude-fable-5.1"
            ];
            thresholdFor = model:
              lib.min
              (model.limit.input - settings.compaction.buffer)
              (1000000 - lib.max 128000 settings.compaction.buffer);
          in
            lib.all (id:
              models.${id}
              == {
                limit.input = 370000;
                compaction.mode = "local";
              }
              && thresholdFor models.${id} == 350000
              && 230000 < thresholdFor models.${id})
            expected;
          assert lib.all (name: lib.hasInfix "model: ${expectedAgentModels.${name}}\n" (frontmatter agents.${name})) (builtins.attrNames expectedAgentModels);
          assert lib.all (prompt: !(lib.hasInfix "model:" (frontmatter prompt))) unpinnedAgentPrompts;
          assert lib.hasInfix "Use this exceptional tier only" buildPrompt;
          assert lib.hasInfix "return control to the caller for canonical routing" buildPrompt;
          # Build re-delegation is constrained by orchestrator handoff guidance,
          # not banned by permissions: keep its task allowances intact.
          assert lib.hasInfix ''resource: "minion"'' (taskPermissions buildPrompt);
          assert lib.hasInfix ''resource: "wise"'' (taskPermissions buildPrompt);
          # Minion may only hand off research (explore) and mechanics (tiny);
          # the exact block keeps every other agent, including upstream
          # built-ins, behind the deny-all default.
          assert lib.hasInfix ''resource: "explore"'' (taskPermissions minionPrompt);
          assert lib.hasInfix ''resource: "tiny"'' (taskPermissions minionPrompt);
          assert !(lib.hasInfix ''resource: "build"'' (taskPermissions minionPrompt));
          # Situational delegation instructions belong to the orchestrator's
          # handoff policy, not any delegated-agent prompt. Compare the shared
          # policy section instead of pinning the test to individual sentences.
          assert lib.hasInfix nestedDelegationPolicy orchestratorPrompt;
          assert lib.all (prompt: !(lib.hasInfix nestedDelegationPolicy prompt)) delegatedPrompts;
          assert lib.all (skill: lib.hasInfix "`${skill}`" jjSkillRouting) [
            "jj-change-management"
            "jj-conflict-resolution"
            "jj-repo-workflow"
            "bay-workspaces"
            "suremac-jj-pr"
          ];
          assert lib.all (owner: lib.hasInfix owner jjSkillRouting) [
            "Local change shaping"
            "Conflict resolution"
            "Lint, sync, push, or ship"
            "Repository acquisition or isolated checkouts"
            "GitHub PR work on suremac"
          ];
          assert lib.hasInfix "exact Bay workspace path" orchestratorPrompt;
          assert lib.all (prompt: !(lib.hasInfix "## Jujutsu skill routing" prompt)) delegatedPrompts;
          # All coding agents share the same open-by-default bash policy.
          # With no opencode-specific override, `opencode run` remains allowed;
          # discouraging it is solely handoff guidance in the policy above.
          assert lib.all (prompt: bashPermissions prompt == buildBashPermissions) codingPrompts;
          assert lib.hasInfix ''resource: "*"'' buildBashPermissions;
          assert !(lib.hasInfix ''effect: ask'' buildBashPermissions);
          assert !(lib.hasInfix ''"opencode run'' buildBashPermissions);
          assert lib.hasInfix ''resource: "rm -rf /"'' buildBashPermissions;
          assert lib.hasInfix ''resource: "rm -rf /Users/chris/*"'' buildBashPermissions;
          assert lib.hasInfix ''resource: "rm -rf /home/chris/*"'' buildBashPermissions;
          assert lib.all (prompt: !(lib.hasInfix "permission:" prompt) && !(lib.hasInfix "variant:" prompt) && !(lib.hasInfix "- action: bash" prompt) && !(lib.hasInfix "- action: task" prompt)) (codingPrompts ++ [agents.plan]);
          # Exercise representative commands against the generated ordered
          # rules, including later overrides and multi-operand guardrails.
          assert lib.all (case: permissionFor case.command == case.expected) deletionCases;
            pkgs.runCommand "opencode-agent-routing-test" {} ''
              mkdir -p $out
              touch $out/success
            '';

        opencode-v2-plugin-contract =
          pkgs.runCommand "opencode-v2-plugin-contract" {
            nativeBuildInputs = [pkgs.nodejs];
          } ''
            node ${./modules/opencode/tests/plugin-v2-contract.mjs} \
              ${./modules/opencode/plugins/dotfiles-direnv.js} \
              ${./modules/opencode/plugins/dotfiles-rust-cache.js}
            mkdir -p "$out"
          '';

        opencode-bay-worktrees-contract =
          pkgs.runCommand "opencode-bay-worktrees-contract" {
            nativeBuildInputs = [pkgs.nodejs];
          } ''
            node ${./modules/opencode/tests/bay-worktrees-contract.mjs} \
              ${./modules/opencode/plugins/dotfiles-bay-worktrees.js} \
              ${opencodePluginRuntime}/node_modules
            mkdir -p "$out"
          '';

        opencode-bay-worktrees-actual-contract = let
          workflow = pkgs.rustPlatform.buildRustPackage {
            pname = "bay-contract";
            version = "0.1.0";
            src = builtins.path {
              path = ./modules/jujutsu/jj-workflow;
              name = "jj-workflow-contract-source";
            };
            cargoLock.lockFile = ./modules/jujutsu/jj-workflow/Cargo.lock;
            doCheck = false;
          };
        in
          pkgs.runCommand "opencode-bay-worktrees-actual-contract" {
            nativeBuildInputs = [pkgs.nodejs pkgs.gitMinimal pkgs.jujutsu];
          } ''
            node ${./modules/opencode/tests/bay-worktrees-actual-contract.mjs} \
              ${./modules/opencode/plugins/dotfiles-bay-worktrees.js} \
              ${opencodePluginRuntime}/node_modules \
              ${workflow}/bin/bay ${pkgs.jujutsu}/bin/jj
            mkdir -p "$out"
          '';

        opencode-session-cleanup-contract =
          pkgs.runCommand "opencode-session-cleanup-contract" {
            nativeBuildInputs = [pkgs.python3];
          } ''
            SESSION_CLEANUP_MODULE=${./modules/opencode/session-cleanup.nix} \
              SESSION_CLEANUP_GUARD=${./modules/opencode/service-guard.sh} \
              python3 ${./modules/opencode/test-session-cleanup.py}
            mkdir -p "$out"
          '';

        nitter-link-stable-path = let
          fakeExtensionV1 = pkgs.runCommand "fake-nitter-link-package-v1" {} ''
            mkdir -p $out/share/nitter-link/chrome $out/share/nitter-link/firefox
            printf '{"manifest_version":3,"name":"nitter-link","version":"0.0.1"}\n' > $out/share/nitter-link/chrome/manifest.json
            printf '{"manifest_version":2,"name":"nitter-link","version":"0.0.1","browser_specific_settings":{"gecko":{"id":"nitter-link@averagechris"}}}\n' > $out/share/nitter-link/firefox/manifest.json
          '';
          fakeExtensionV2 = pkgs.runCommand "fake-nitter-link-package-v2" {} ''
            mkdir -p $out/share/nitter-link/chrome $out/share/nitter-link/firefox
            printf '{"manifest_version":3,"name":"nitter-link","version":"0.0.2"}\n' > $out/share/nitter-link/chrome/manifest.json
            printf '{"manifest_version":2,"name":"nitter-link","version":"0.0.2","browser_specific_settings":{"gecko":{"id":"nitter-link@averagechris"}}}\n' > $out/share/nitter-link/firefox/manifest.json
          '';
          mkTestConfig = extensionPackage:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit dotfiles_lib inputs system;
                sshKeys = inputs.base-lib.sshKeys;
                secrets = {};
              };
              modules = [
                ./modules/nitter-link.nix
                {
                  home.username = "test";
                  home.homeDirectory = "/tmp/test-home";
                  home.stateVersion = "26.05";
                  programs.nitter-link = {
                    enable = true;
                    chromiumBrowsers.helium = {
                      enable = true;
                      inherit extensionPackage;
                      stablePath = "/tmp/test-home/.config/net.imput.helium/nitter-link";
                    };
                    firefoxBrowsers.zen = {
                      enable = true;
                      inherit extensionPackage;
                      temporaryManual = {
                        enable = true;
                        stablePath = "/tmp/test-home/.config/zen/nitter-link-temporary";
                      };
                    };
                  };
                }
              ];
            };
          configV1 = mkTestConfig fakeExtensionV1;
          configV2 = mkTestConfig fakeExtensionV2;
          chromeKey = "net.imput.helium/nitter-link";
          zenKey = "zen/nitter-link-temporary";
          chromeSourceV1 = configV1.config.xdg.configFile.${chromeKey}.source;
          chromeSourceV2 = configV2.config.xdg.configFile.${chromeKey}.source;
          zenSourceV1 = configV1.config.xdg.configFile.${zenKey}.source;
          zenSourceV2 = configV2.config.xdg.configFile.${zenKey}.source;
        in
          pkgs.runCommand "nitter-link-stable-path-test" {} ''
            test "${chromeSourceV1}" = "${fakeExtensionV1}/share/nitter-link/chrome"
            test "${chromeSourceV2}" = "${fakeExtensionV2}/share/nitter-link/chrome"
            test "${zenSourceV1}" = "${fakeExtensionV1}/share/nitter-link/firefox"
            test "${zenSourceV2}" = "${fakeExtensionV2}/share/nitter-link/firefox"
            test -f "${chromeSourceV1}/manifest.json"
            test -f "${chromeSourceV2}/manifest.json"
            test -f "${zenSourceV1}/manifest.json"
            test -f "${zenSourceV2}/manifest.json"
            touch $out
          '';

        agent-skill-bundle-audit = let
          auditLib = import ./modules/agent-skills-lib.nix {inherit (nixpkgs) lib;};
          audit = expectedNames:
            auditLib.auditBundle {
              sourceDirectory = inputs.rdny + "/skills";
              layout = "directories";
              inherit expectedNames;
            };
          matched = audit ["rdny-browser"];
          added = audit [];
          removed = audit ["rdny-browser" "retired-skill"];
          renderNames = names:
            if names == []
            then "none"
            else nixpkgs.lib.concatStringsSep ", " names;
        in
          pkgs.runCommand "agent-skill-bundle-audit-test" {} ''
            test '${nixpkgs.lib.boolToString matched.matches}' = true
            test '${renderNames added.added}' = rdny-browser
            test '${renderNames added.removed}' = none
            test '${renderNames removed.added}' = none
            test '${renderNames removed.removed}' = retired-skill
            touch $out
          '';

        agent-skill-deployment-yaml-negative = let
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              ./modules/agent-skills.nix
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = pkgs.hello;
                dotfiles.agentSkills.broken.source = ./tests/agent-skills/malformed/skills/broken/SKILL.md;
              }
            ];
          };
          deployed = testConfig.config.xdg.configFile."opencode/skills/broken";
          manifest = pkgs.writeText "malformed-deployed-skill.json" (builtins.toJSON [
            {
              destination = "opencode/skills/broken";
              source = toString deployed.source;
            }
          ]);
        in
          pkgs.runCommand "agent-skill-deployment-yaml-negative" {
            nativeBuildInputs = [(pkgs.python3.withPackages (python: [python.pyyaml]))];
          } ''
            if python3 ${./modules/opencode/tests/check-deployed-skills.py} ${manifest}; then
              echo "externally sourced malformed deployed skill unexpectedly passed" >&2
              exit 1
            fi
            mkdir -p "$out"
          '';

        rdny-module-completions-and-skills = let
          fakeRdny = pkgs.writeShellApplication {
            name = "rdny";
            text = ''
              case "$1" in
                completion)
                  case "$2" in
                    bash) printf 'complete -F _rdny rdny\n' ;;
                    fish) printf 'complete -c rdny\n' ;;
                    zsh) printf '#compdef rdny\n' ;;
                    *) exit 64 ;;
                  esac
                  ;;
                *) exit 64 ;;
              esac
            '';
          };
          fakeRdnySkill = pkgs.writeText "fake-rdny-browser-SKILL.md" ''
            ---
            name: rdny-browser
            description: test rdny browser skill
            ---
            # rdny browser automation
          '';
          fakeRdnySkillPatch = pkgs.writeText "fake-rdny-browser.patch" ''
            --- a/SKILL.md
            +++ b/SKILL.md
            @@ -6 +6 @@
            -# rdny browser automation
            +# patched rdny browser automation
          '';
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              inherit dotfiles_lib inputs system;
              sshKeys = inputs.base-lib.sshKeys;
              secrets = {};
            };
            modules = [
              ./modules/rdny.nix
              ({lib, ...}: {
                options.dotfiles.opencode.agentTools = lib.mkOption {
                  type = lib.types.listOf lib.types.attrs;
                  default = [];
                };
              })
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = fakeRdny;
                dotfiles.rdny = {
                  enable = true;
                  package = fakeRdny;
                  environment = {
                    maxDownloadBytes = 1048576;
                    maxRecordingSeconds = 120;
                  };
                };
                dotfiles.agentSkills.rdny-browser = {
                  source = fakeRdnySkill;
                  patches = [fakeRdnySkillPatch];
                  extraText = "## Host workflow\n\nUse the host wrapper.\n";
                };
                dotfiles.agentSkillBundles.rdny.sourceDirectory = inputs.rdny + "/skills";
              }
            ];
          };
          rdnyCompletionPackages = builtins.filter (pkg: nixpkgs.lib.hasPrefix "rdny-completions" (pkg.name or "")) testConfig.config.home.packages;
          rdnyCompletions = builtins.head rdnyCompletionPackages;
          rdnySkill = testConfig.config.xdg.configFile."opencode/skills/rdny-browser".source + "/SKILL.md";
        in
          pkgs.runCommand "rdny-module-completions-and-skills-test" {} ''
            test ${toString (builtins.length rdnyCompletionPackages)} -eq 1
            test -f ${rdnyCompletions}/share/bash-completion/completions/rdny
            test -f ${rdnyCompletions}/share/fish/vendor_completions.d/rdny.fish
            test -f ${rdnyCompletions}/share/zsh/site-functions/_rdny
            ${pkgs.gnugrep}/bin/grep -q '^name: rdny-browser$' ${rdnySkill}
            ${pkgs.gnugrep}/bin/grep -q '^# patched rdny browser automation$' ${rdnySkill}
            ${pkgs.gnugrep}/bin/grep -q '^## Host workflow$' ${rdnySkill}
            ${pkgs.gnugrep}/bin/grep -q '^Use the host wrapper.$' ${rdnySkill}
            if ${pkgs.gnugrep}/bin/grep -q 'install-rdny-opencode-skills' ${testConfig.activationPackage}/activate; then
              echo "rdny skills must be linked from a build-time derivation" >&2
              exit 1
            fi
            test '${testConfig.config.home.sessionVariables.RDNY_MAX_DOWNLOAD_BYTES}' = 1048576
            test '${testConfig.config.home.sessionVariables.RDNY_MAX_RECORDING_SECONDS}' = 120
            touch $out
          '';

        srht-config-rendering = let
          fakeSrht = pkgs.writeShellScriptBin "srht" ''
            echo "srht test package"
          '';
          fakeSrhtSkills = pkgs.runCommand "fake-srht-skills" {} ''
            mkdir -p "$out"
            printf 'srht-issues\n' > "$out/srht-issues.md"
            printf 'srht-ci\n' > "$out/srht-ci.md"
            printf 'srht-setup\n' > "$out/srht-setup.md"
          '';
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              inherit inputs system;
            };
            modules = [
              ./modules/srht.nix
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = fakeSrht;
                dotfiles.srht = {
                  enable = true;
                  package = fakeSrht;
                };
                dotfiles.agentSkills = {
                  srht-issues = {
                    enable = false;
                    source = fakeSrhtSkills + "/srht-issues.md";
                  };
                  srht-ci.source = fakeSrhtSkills + "/srht-ci.md";
                  srht-setup = {
                    enable = false;
                    source = fakeSrhtSkills + "/srht-setup.md";
                  };
                };
                dotfiles.agentSkillBundles.srht.sourceDirectory = inputs.srht + "/assets/skills";
              }
            ];
          };
          rendered = testConfig.config.xdg.configFile."srht/config.toml".source;
          srhtCiSkill = testConfig.config.xdg.configFile."opencode/skills/srht-ci".source + "/SKILL.md";
        in
          pkgs.runCommand "srht-config-rendering-test" {} ''
            ${pkgs.gnugrep}/bin/grep -q '^ttl-minutes = 30$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^mode = "error"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^\[profiles.work\]$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^instance = "sr.ht"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^tracker = "~averagechris/projects"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^project = "~averagechris/projects"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^done-resolution = "fixed"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^\[\[profiles.work.todo-policy.context-labels\]\]$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^value = "repo:{repo}"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^add-on-create = true$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^filter-reads = true$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^require-on-tracker = true$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^any-label = \["fix", "security"\]$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^create = "warn"$' ${rendered}
            ${pkgs.gnugrep}/bin/grep -q '^existing = "off"$' ${rendered}
            test '${testConfig.config.home.sessionVariables.SRHT_PROFILE}' = work
            if ${pkgs.gnugrep}/bin/grep -q '^\[\[routes\]\]$' ${rendered}; then
              echo "profile-only srht config unexpectedly contains routes" >&2
              exit 1
            fi
            if ${pkgs.gnugrep}/bin/grep -q '^token' ${rendered}; then
              echo "rendered srht config unexpectedly contains token configuration" >&2
              exit 1
            fi
            test "$(cat ${srhtCiSkill})" = srht-ci
            test ${
              if builtins.hasAttr "opencode/skills/srht-issues" testConfig.config.xdg.configFile
              then "1"
              else "0"
            } -eq 0
            if ${pkgs.gnugrep}/bin/grep -q 'install-srht-opencode-skills' ${testConfig.activationPackage}/activate; then
              echo "srht skills must be linked declaratively" >&2
              exit 1
            fi
            touch $out
          '';

        gander-module-config-and-skills = let
          fakeGander = pkgs.writeShellScriptBin "gander" "exit 0";
          fakeGanderSkills = pkgs.runCommand "fake-gander-skills" {} ''
            mkdir -p "$out/gander-review" "$out/gander-address-review"
            printf 'gander-review\n' > "$out/gander-review/SKILL.md"
            printf 'gander-address-review\n' > "$out/gander-address-review/SKILL.md"
          '';
          testConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              inherit dotfiles_lib inputs system;
              sshKeys = inputs.base-lib.sshKeys;
              secrets = {};
            };
            modules = [
              ./modules/gander.nix
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home";
                home.stateVersion = "26.05";
                programs.opencode.enable = true;
                programs.opencode.package = fakeGander;
                dotfiles.gander = {
                  enable = true;
                  package = fakeGander;
                  config = {
                    ignore.globs = ["vendor/**"];
                    jj.binary = "/nix/store/fake-jj/bin/jj";
                    artifact = {
                      format = "json";
                      profile = "agent";
                      outputDir = "reviews";
                      basename = "result";
                      onTuiQuit = "write";
                    };
                    generated = {
                      presets = ["lockfiles" "api-clients"];
                      globs = ["generated/**"];
                    };
                    syntax = {
                      enabled = true;
                      languages = ["nix" "rust"];
                      mappings = [
                        {
                          name = "nix";
                          extensions = ["nix.in"];
                          filenames = ["flake-template"];
                        }
                      ];
                      theme.keyword = "magenta bold";
                    };
                    limits = {
                      maxDiffLines = 7000;
                      nudgeDiffLines = 1200;
                      nudgeFiles = 30;
                    };
                    agent = {
                      name = "review-agent";
                    };
                    identity = {
                      name = "Test Reviewer";
                      email = "reviewer@example.com";
                    };
                    diff = {
                      wordHighlight = false;
                      lineBackground = true;
                      gutterBar = true;
                      view = "side-by-side";
                      softWrap = false;
                      contextStep = 12;
                      theme.added-line-bg = "#102010";
                    };
                    comments = {
                      initialState = "draft";
                      defaultChannel = "collaboration";
                    };
                    theme = {
                      mode = "dark";
                      transparent = false;
                    };
                    ui = {
                      filePaneAutoHideWidth = 60;
                      filePaneSplitPercent = 35;
                      menuBar = true;
                    };
                    keybindings = {
                      preset = "hunk";
                      quit = ["Q"];
                      spotlight-previous = ["alt-h"];
                    };
                  };
                  # Prove the raw escape hatch is last: this replaces the typed
                  # value while leaving the other typed sections intact.
                  settings.diff.soft-wrap = true;
                };
                dotfiles.agentSkills = {
                  gander-review.source = fakeGanderSkills + "/gander-review/SKILL.md";
                  gander-address-review = {
                    enable = false;
                    source = fakeGanderSkills + "/gander-address-review/SKILL.md";
                  };
                };
                dotfiles.agentSkillBundles.gander.sourceDirectory = inputs.gander + "/skills";
              }
            ];
          };
          renderedConfig = testConfig.config.xdg.configFile."gander/config.toml".source;
          ganderReviewSkill = testConfig.config.xdg.configFile."opencode/skills/gander-review".source + "/SKILL.md";
          disabledSkillsConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              inherit dotfiles_lib inputs system;
              sshKeys = inputs.base-lib.sshKeys;
              secrets = {};
            };
            modules = [
              ./modules/gander.nix
              {
                home.username = "test";
                home.homeDirectory = "/tmp/test-home-disabled";
                home.stateVersion = "26.05";
                programs.opencode.enable = false;
                dotfiles.gander = {
                  enable = true;
                  package = fakeGander;
                };
                dotfiles.agentSkillBundles.gander.sourceDirectory = inputs.gander + "/skills";
              }
            ];
          };
        in
          pkgs.runCommand "gander-module-config-and-skills-test" {} ''
            config=${renderedConfig}
            ${pkgs.gnugrep}/bin/grep -q '^\[ignore\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[jj\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[artifact\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^output_dir = "reviews"$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^on_tui_quit = "write"$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[generated\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[syntax\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[\[syntax.mappings\]\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[syntax.theme\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[limits\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^max-diff-lines = 7000$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[agent\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[diff\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^soft-wrap = true$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[diff.theme\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[comments\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^initial-state = "draft"$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^default-channel = "collaboration"$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[identity\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[theme\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[ui\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^\[keybindings\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^preset = "hunk"$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^spotlight-previous = \["alt-h"\]$' "$config"

            activate=${testConfig.activationPackage}/activate
            test "$(cat ${ganderReviewSkill})" = gander-review
            test ${
              if builtins.hasAttr "opencode/skills/gander-address-review" testConfig.config.xdg.configFile
              then "1"
              else "0"
            } -eq 0
            if ${pkgs.gnugrep}/bin/grep -q 'install-gander-opencode-skills' "$activate"; then
              echo "Gander skills must be linked declaratively" >&2
              exit 1
            fi
            touch $out
          '';
      };
    });
}
