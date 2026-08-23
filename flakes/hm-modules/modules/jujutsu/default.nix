{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.jujutsu;
  dotCfg = config.dotfiles.jujutsu;
  compactLogTemplate = lib.concatStrings [
    "if(current_working_copy, \"@ \", \"  \")"
    " ++ change_id.short()"
    " ++ \" \" ++ commit_id.short()"
    " ++ \" \" ++ if(empty, \"(empty) \", \"\")"
    " ++ if(bookmarks, bookmarks ++ \" \", \"\")"
    " ++ if(tags, tags ++ \" \", \"\")"
    " ++ coalesce(description.first_line(), \"(no description set)\")"
    " ++ \"\\n\""
  ];
  compactLogArgs = ["log" "--no-graph" "--no-pager" "--color=never" "-T" compactLogTemplate];
  compactLogRevset = revset: compactLogArgs ++ ["-r" revset];
  jjWorkflow = pkgs.rustPlatform.buildRustPackage {
    pname = "jj-workflow";
    version = "0.1.0";
    src = ./jj-workflow;

    cargoLock = {
      lockFile = ./jj-workflow/Cargo.lock;
      outputHashes = {};
    };

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    nativeCheckInputs = with pkgs; [
      gitMinimal
      jujutsu
      nodejs
    ];

    preCheck = ''
      export HOME="$TMPDIR/home"
      export XDG_CONFIG_HOME="$HOME/.config"
      mkdir -p "$XDG_CONFIG_HOME"
      jj config set --user user.name jj-workflow-tests
      jj config set --user user.email jj-workflow-tests@example.invalid
    '';

    postFixup = ''
      wrapProgram $out/bin/jj-workflow \
        --prefix PATH : ${lib.makeBinPath ([
          pkgs.fzf
          pkgs.jujutsu
          config.programs.git.package
          pkgs.direnv
          pkgs.docker
        ]
        ++ lib.optional dotCfg.prWorkflow.enable pkgs.gh)}
    '';

    meta = {
      description = "Workflow helpers for jj ship, tag-push, and sync";
      license = lib.licenses.mit;
    };
  };
in {
  options.dotfiles.jujutsu.workspaces = with lib; {
    projectGroups = mkOption {
      type = types.listOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Project group directory containing related jj repositories.";
          };
          workspaceDir = mkOption {
            type = types.str;
            default = "ws";
            description = "Workspace namespace directory under the project group.";
          };
        };
      });
      default = [{path = "~/projects";}];
      description = "Project groups used by the jj ws workflow helper.";
    };

    fetchRemote = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Remote to fetch for jj ws add when multiple remotes exist.";
    };

    cloneArtifacts = mkOption {
      type = types.listOf types.str;
      default = [
        ".direnv"
        "target"
        "node_modules"
        ".venv"
      ];
      description = ''
        Directory basenames that jj ws add CoW-clones from the source checkout
        into new workspaces. An empty list disables artifact cloning.
      '';
    };
  };

  options.dotfiles.jujutsu.prWorkflow = with lib; {
    enable = mkEnableOption "jj pr GitHub pull request workflow helper";

    autoBookmark = mkOption {
      type = types.bool;
      default = true;
      description = "Whether jj pr create may create a bookmark when none is inferred and --ticket is provided.";
    };

    bookmarkTemplate = mkOption {
      type = types.str;
      default = "{whoami}/{ticket-number}/{short-description}";
      description = "Template used by jj pr auto-bookmarking. Supported placeholders: {whoami}, {ticket-number}, {short-description}.";
    };
  };

  options.dotfiles.jujutsu.workflowAliases.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Enable repository workflow aliases backed by jj-workflow, including lint,
      ship, sync, push, tag-push, workspace helpers, and optional PR helpers.
      Disable this on narrow servers that only need basic jj commands and should
      not retain the workflow helper runtime closure.
    '';
  };

  config.programs.jujutsu = lib.mkIf cfg.enable {
    settings = {
      user = {
        name = lib.mkDefault "chris";
        email = lib.mkDefault "chris@thesogu.com";
      };
      aliases =
        {
          df = ["jj" "diff" "--from" "trunk()"];
          ll = ["log" "-r" "ancestors(@) | descendants(@)"];
          ld = ["log" "-r" "descendants(@)"];
          la = ["log" "-r" "ancestors(@)"];
          log-all = ["log" "-r" "all()"];
          # Agent-friendly compact log forms. `log-summary` accepts normal
          # `jj log` flags, so e.g. `jj log-summary -r 'trunk()::' --limit 10`
          # replaces the long hand-written template agents often reach for.
          log-summary = compactLogArgs;
          log-recent = compactLogArgs ++ ["--limit" "10"];
          log-here = compactLogRevset "@ | @-";
          log-stack = compactLogRevset "trunk()::@";
          log-ahead = compactLogRevset "trunk()..@";
          # Move the closest ancestor bookmark to the parent of your working copy (@-):
          tug = ["bookmark" "move" "--from" "heads(::@- & bookmarks())" "--to" "@-"];

          # change (edit) to a bookmark
          ch = with pkgs; let
            script = writeShellApplication {
              name = "jj-ch";
              runtimeInputs = [jujutsu fzf coreutils];
              text = ''
                set -euo pipefail

                # Count local bookmarks
                count="$(jj bookmark list -T 'self.name() ++ "\n"' | wc -l)"

                if [ "''${count}" = "1" ]; then
                  # Get the only bookmark name
                  only="$(jj bookmark list -T 'self.name()')"

                  # If current change (@) is a descendant of that bookmark, do nothing
                  if jj log --no-graph -r "descendants(bookmarks(\"''${only}\")) & @" -n 1 | grep -q .; then
                    # No-op
                    exit 0
                  fi
                  # else fall through to create a child on that bookmark
                fi

                # Fuzzy-pick a bookmark (shows name, short id, first-line desc)
                sel="$(
                  jj bookmark list \
                    -T 'self.name() ++ "\t" ++ coalesce(self.normal_target().commit_id().short(), "") ++ "\t" ++ coalesce(self.normal_target().description().first_line(), "") ++ "\n"' \
                    | fzf --query "''${1:-}" --exit-0 --select-1
                )" || exit 0

                name="$(printf '%s' "''${sel}" | cut -f1)"

                # Create a new change on top of the selected bookmark target
                jj new -r "bookmarks(\"''${name}\")"
              '';
            };
          in ["util" "exec" "--" "${script}/bin/jj-ch"];

          prune = with pkgs; let
            script = writeShellApplication {
              name = "jj-prune-stale";
              runtimeInputs = [jujutsu fzf coreutils];
              text = ''
                set -euo pipefail

                remote="''${1:-origin}"

                # Refresh remote refs and import into jj view
                jj git fetch "$remote"
                jj git import

                # Build a tab-separated list of stale bookmarks:
                # name, short commit id, first-line description
                # Condition: tracked() && !tracking_present()
                list_cmd=(
                  jj bookmark list
                  -T 'if(self.tracked() && !self.tracking_present(),
                          self.name() ++ "\t"
                          ++ coalesce(self.normal_target().commit_id().short(), "")
                          ++ "\t"
                          ++ coalesce(self.normal_target().description().first_line(), "")
                          ++ "\n",
                        "")'
                )

                # Let user confirm via fzf, with all selected by default
                sel="$(
                  "''${list_cmd[@]}" \
                    | sed '/^$/d' \
                    | fzf --multi --bind 'start:select-all' \
                          --header 'Prune local bookmarks whose upstream no longer exists'
                )" || exit 0

                [ -z "$sel" ] && {
                  echo "No bookmarks selected."
                  exit 0
                }

                echo "Pruning bookmarks:"
                printf '%s\n' "$sel" | cut -f1 | sed 's/^/ - /'

                # Delete selected bookmarks locally
                printf '%s\n' "$sel" | while IFS= read -r line; do
                  name="$(printf '%s' "$line" | cut -f1)"
                  [ -n "$name" ] && jj bookmark delete "$name"
                done
              '';
            };
          in ["util" "exec" "--" "${script}/bin/jj-prune-stale"];
        }
        // lib.optionalAttrs dotCfg.workflowAliases.enable {
          # Run repo-configured lints without pushing; `jj lint onboard` discovers
          # candidate commands when a repo has not been configured yet.
          lint = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "lint"];

          # Complete workflow: finish current change and push the parent of the
          # working copy to remote so an already-empty `@` does not get shipped.
          # Refuses empty targets and requires an explicit --bookmark instead of
          # silently falling back to integration bookmarks.
          ship = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "ship"];

          # Publish human/agent-created release tags. `jj tag push` cannot be
          # expressed as a jj alias because aliases cannot override built-ins.
          tag-push = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "tag" "push"];

          # Sync with upstream: fetch, then rebase onto the integration bookmark
          sync = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "sync"];

          # Jujutsu workspace management.
          ws = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "ws"];

          # Push with pre-push lints (configurable per-repo)
          # Or skip lints entirely with: jj git push
          # Configure lints in .jj-lint.toml (VCS-tracked) or repo config (.jj/repo/config.toml)
          push = with pkgs; let
            script = writeShellApplication {
              name = "jj-push";
              runtimeInputs = [jujutsu];
              text = ''
                set -euo pipefail

                ${jjWorkflow}/bin/jj-workflow lint

                echo ""
                echo "Lints passed! Pushing..."
                jj git push "$@"
              '';
            };
          in ["util" "exec" "--" "${script}/bin/jj-push"];
        }
        // lib.optionalAttrs (dotCfg.workflowAliases.enable && dotCfg.prWorkflow.enable) {
          # GitHub PR workflow for jj workspaces. Disabled by default and enabled
          # only on hosts that use GitHub work repositories from non-colocated jj
          # workspaces.
          pr = ["util" "exec" "--" "${jjWorkflow}/bin/jj-workflow" "pr"];
        };
      scope = [
        {
          paths = ["~/sureapp/**"];
          user = {
            name = "Chris Cummings";
            email = "chris.cummings@sureapp.com";
          };
        }
      ];
      dotfiles.workspaces =
        {
          copy-envrc = "untracked";
          venv-mode = "copy";
          direnv-allow = true;
          docker-cleanup = "auto";
          docker-remove-volumes = true;
          picker = "fzf";
          clone-artifacts = dotCfg.workspaces.cloneArtifacts;
          project-groups = map (group: "${group.path}:${group.workspaceDir}") dotCfg.workspaces.projectGroups;
        }
        // lib.optionalAttrs (dotCfg.workspaces.fetchRemote != null) {
          fetch-remote = dotCfg.workspaces.fetchRemote;
        };
      dotfiles.pr = lib.mkIf dotCfg.prWorkflow.enable {
        auto-bookmark = dotCfg.prWorkflow.autoBookmark;
        bookmark-template = dotCfg.prWorkflow.bookmarkTemplate;
      };
      signing = lib.mkIf (!config.dotfiles.gpg.enable) {
        # When gpg module is not enabled, use the hardcoded signing key
        # When gpg module is enabled, it manages jj config during activation
        key = "E026151F78807B8E6012590F623745A83D6C9C02";
        behavior = "own";
        backend = "gpg";
      };
    };
  };
  config.programs.starship.settings = lib.mkIf cfg.enable (let
    starshipJj = inputs.starship-jj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    "$schema" = "https://starship.rs/config-schema.json";
    format = "$directory\${custom.jj}\${custom.env} $all";
    git_branch = {disabled = true;};
    git_commit = {disabled = true;};
    git_state = {disabled = true;};
    git_status = {disabled = true;};
    git_metrics = {disabled = true;};
    vcsh = {disabled = true;};
    command_timeout = 1200;
    aws = {disabled = true;}; # hide AWS module
    nix_shell = {disabled = true;};
    package = {
      format = "[$symbol$version]($style) ";
      symbol = "📦";
    };
    rust = {
      format = "[$symbol$version]($style) ";
      symbol = "🦀";
    };
    custom = {
      jj = {
        description = "jj via starship-jj plugin";
        format = "$output ";
        ignore_timeout = true;
        when = true;
        use_stdin = false;
        # call the flake-provided binary via inputs
        shell = [
          "${starshipJj}/bin/starship-jj"
          "--ignore-working-copy"
          "starship"
        ];
        command = "prompt";
      };

      env = {
        description = "Show activated dev envs (direnv/mise/nix)";
        when = "[ -n \"$DIRENV_DIR\" ] || [ -n \"$MISE_ACTIVE\" ] || [ -n \"$NIX_ENVIRONMENT\" ] || [ -n \"$IN_NIX_SHELL\" ]";
        use_stdin = false;
        shell = ["sh" "-lc"];
        command = ''
          direnv=""
          mise=""
          out=""
          if [ -n "''${DIRENV_DIR-}" ]; then direnv="direnv"; fi
          if [ -n "''${MISE_ACTIVE-}" ]; then mise="mise"; fi

          nix=""
          if [ -n "''${NIX_SHELL_NAME-}" ]; then
            nix="nix:''${NIX_SHELL_NAME}"
          elif [ -n "''${NIX_ENVIRONMENT-}" ]; then
            nix="nix:''${NIX_ENVIRONMENT}"
          elif [ -n "''${IN_NIX_SHELL-}" ]; then
            nix="nix"
          fi

          if [ -n "$nix" ]; then
            if [ -n "$direnv" ]; then
              direnv="$direnv($nix)"
            elif [ -n "$mise" ]; then
              mise="$mise($nix)"
            else
              out="$nix"
            fi
          fi

          if [ -n "$direnv" ]; then
            out="$direnv"
          fi
          if [ -n "$mise" ]; then
            if [ -n "$out" ]; then out="$out $mise"; else out="$mise"; fi
          fi

          printf '%s' "$out"
        '';
        format = "[$output](bold blue) ";
      };
    };
  });
}
