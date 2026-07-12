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
      inputs.srht.follows = "srht";
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
            upstreamHashes = builtins.fromJSON (builtins.readFile "${opencodeInput}/nix/hashes.json");
            nodeModulesOverrides = {
              "3b7a5e783d59e8986dca6e5df48663613fa80722" = {
                hash.aarch64-darwin = "sha256-81IAmdjiYZz8IgMJt0+VxzdOS80gTHc5SendwEW/vD4=";
              };
              "0f272d931d806681a0f7f19538e2f3f1d52d1832" = {
                hash.aarch64-darwin = "sha256-+lx7mv1QM+nl3UPY9GxPcbWlhK4TKYp96rvJd51Exig=";
                postPatch = ''
                  substituteInPlace bun.lock \
                    --replace-fail '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#20bd361", {}, "anomalyco-ghostty-web-20bd361", "sha512-dW0nwaiBBcun9y5WJSvm3HxDLe5o9V0xLCndQvWonRVubU8CS1PHxZpLffyPt1YujPWC13ez03aWxcuKBPYYGQ=="]' \
                                   '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#513463a", {}, "anomalyco-ghostty-web-513463a", "sha512-GZR8LSmgGzViWnBJrqRI8MpAZRCJxhcr1Hi9Tyeh7YRooHZQjK9J97FQRD3tbBaM2wjq05gzGY2UEsG+JtZeBw=="]'
                '';
              };
            };
            override = nodeModulesOverrides.${opencodeInput.rev or ""} or {};
            hasSystemOverride = builtins.hasAttr system (override.hash or {});
            node_modules =
              (final.callPackage "${opencodeInput}/nix/node_modules.nix" {
                inherit rev;
                hash =
                  (override.hash or {}).${system} or upstreamHashes.nodeModules.${system};
              }).overrideAttrs (old: {
                postPatch = (old.postPatch or "") + (final.lib.optionalString hasSystemOverride (override.postPatch or ""));
              });
          in {
            titlecase = base-lib.inputs.titlecase.packages.${system}.default;
            pi-coding-agent = final.callPackage ../base-lib/packages/pi-coding-agent.nix {};
            pi = final.pi-coding-agent;
            helium-bin = final.callPackage ../base-lib/packages/helium-bin.nix {};
            nitter-link-chrome-extension = inputs.nitter-link.packages.${system}.chrome-extension;
            nitter-link-firefox-extension = inputs.nitter-link.packages.${system}.firefox-extension;
            notion-cli = final.callPackage ../base-lib/packages/notion-cli.nix {};
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
    in {
      checks = {
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
                skills)
                  test "$2" = install
                  shift 2
                  while [ "$#" -gt 0 ]; do
                    case "$1" in
                      --dir) shift; skills_dir="$1" ;;
                      --force) force=1 ;;
                    esac
                    shift || true
                  done
                  test -n "''${skills_dir:-}"
                  test "''${force:-}" = 1
                  ;;
                *) exit 64 ;;
              esac
            '';
          };
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
                dotfiles.rdny = {
                  enable = true;
                  package = fakeRdny;
                  environment = {
                    maxDownloadBytes = 1048576;
                    maxRecordingSeconds = 120;
                  };
                };
              }
            ];
          };
          rdnyCompletionPackages = builtins.filter (pkg: nixpkgs.lib.hasPrefix "rdny-completions" (pkg.name or "")) testConfig.config.home.packages;
          rdnyCompletions = builtins.head rdnyCompletionPackages;
        in
          pkgs.runCommand "rdny-module-completions-and-skills-test" {} ''
            test ${toString (builtins.length rdnyCompletionPackages)} -eq 1
            test -f ${rdnyCompletions}/share/bash-completion/completions/rdny
            test -f ${rdnyCompletions}/share/fish/vendor_completions.d/rdny.fish
            test -f ${rdnyCompletions}/share/zsh/site-functions/_rdny
            ${pkgs.gnugrep}/bin/grep -q 'skills install' ${testConfig.activationPackage}/activate
            ${pkgs.gnugrep}/bin/grep -q -- '--dir "\$skills_dir"' ${testConfig.activationPackage}/activate
            ${pkgs.gnugrep}/bin/grep -q -- '--force' ${testConfig.activationPackage}/activate
            test '${testConfig.config.home.sessionVariables.RDNY_MAX_DOWNLOAD_BYTES}' = 1048576
            test '${testConfig.config.home.sessionVariables.RDNY_MAX_RECORDING_SECONDS}' = 120
            touch $out
          '';

        srht-config-rendering = let
          fakeSrht = pkgs.writeShellScriptBin "srht" ''
            echo "srht test package"
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
                dotfiles.srht = {
                  enable = true;
                  package = fakeSrht;
                  opencodeSkills.enable = false;
                };
              }
            ];
          };
          rendered = testConfig.config.xdg.configFile."srht/config.toml".source;
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
            touch $out
          '';

        gander-module-config-and-skills = let
          fakeGander = pkgs.writeShellApplication {
            name = "gander";
            runtimeInputs = [pkgs.coreutils];
            text = ''
              test "$1" = skills
              test "$2" = install
              shift 2
              names=()
              force=
              while [ "$#" -gt 0 ]; do
                case "$1" in
                  --dir) shift; skills_dir="$1" ;;
                  --force) force=1 ;;
                  *) names+=("$1") ;;
                esac
                shift
              done
              test -n "''${skills_dir:-}"
              if [ "''${#names[@]}" -eq 0 ]; then
                names=(gander-review gander-address-review)
              fi
              mkdir -p "$skills_dir"
              for name in "''${names[@]}"; do
                mkdir -p "$skills_dir/$name"
                target="$skills_dir/$name/SKILL.md"
                if [ -e "$target" ] && [ -z "$force" ]; then
                  exit 1
                fi
                printf '%s\n' "$name" > "$target"
              done
            '';
          };
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
                      command = "opencode run";
                      autostart = false;
                      prompt = "Review {repo} at {rev}";
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
                    comments.initialState = "draft";
                    keybindings = {
                      quit = ["Q"];
                      zen-artifact-previous = ["alt-h"];
                    };
                  };
                  # Prove the raw escape hatch is last: this replaces the typed
                  # value while leaving the other typed sections intact.
                  settings.diff.soft-wrap = true;
                  skills = {
                    names = ["gander-review"];
                    targetDirectory = "/tmp/test-home/.config/opencode/skills";
                  };
                };
              }
            ];
          };
          renderedConfig = testConfig.config.xdg.configFile."gander/config.toml".source;
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
            ${pkgs.gnugrep}/bin/grep -q '^\[keybindings\]$' "$config"
            ${pkgs.gnugrep}/bin/grep -q '^zen-artifact-previous = \["alt-h"\]$' "$config"

            activate=${testConfig.activationPackage}/activate
            ${pkgs.gnugrep}/bin/grep -q 'skills install' "$activate"
            ${pkgs.gnugrep}/bin/grep -q 'gander-review' "$activate"
            ${pkgs.gnugrep}/bin/grep -q -- '--dir "\$skills_dir"' "$activate"
            ${pkgs.gnugrep}/bin/grep -q -- '--force' "$activate"
            if ${pkgs.gnugrep}/bin/grep -q 'skills install' ${disabledSkillsConfig.activationPackage}/activate; then
              echo "Gander skill activation must be absent when OpenCode is disabled" >&2
              exit 1
            fi

            # Exercise the packaged installer contract twice: the default
            # force behavior makes repeated activation safe and only the
            # selected skill subtree is touched.
            mkdir -p work/skills/unrelated
            touch work/skills/unrelated/keep
            ${fakeGander}/bin/gander skills install gander-review --dir "$PWD/work/skills" --force
            ${fakeGander}/bin/gander skills install gander-review --dir "$PWD/work/skills" --force
            test -f work/skills/gander-review/SKILL.md
            test -f work/skills/unrelated/keep
            mkdir -p work/all-skills
            ${fakeGander}/bin/gander skills install --dir "$PWD/work/all-skills" --force
            test -f work/all-skills/gander-review/SKILL.md
            test -f work/all-skills/gander-address-review/SKILL.md
            touch $out
          '';
      };
    });
}
