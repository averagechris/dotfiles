{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.jujutsu;
in {
  config.programs.jujutsu = lib.mkIf cfg.enable {
    settings = {
      user = {
        name = lib.mkDefault "chris";
        email = lib.mkDefault "chris@thesogu.com";
      };
      aliases = {
        df = ["jj" "diff" "--from" "trunk()"];
        ll = ["log" "-r" "ancestors(@) | descendants(@)"];
        ld = ["log" "-r" "descendants(@)"];
        la = ["log" "-r" "ancestors(@)"];
        log-all = ["log" "-r" "all()"];
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

                # If current change (@) is an descendant of that bookmark, do nothing
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

        # Run repo-configured lints without pushing
        # Configure lints in .jj-lint.toml (VCS-tracked) or repo config (.jj/repo/config.toml):
        #   lints = ["alejandra --check .", "statix check"]
        lint = with pkgs; let
          script = writeShellApplication {
            name = "jj-lint";
            runtimeInputs = [jujutsu coreutils fd shellcheck alejandra statix gnused yj jq];
            text = ''
              set -euo pipefail

              # Terminal width for formatting (default 80)
              term_width="''${COLUMNS:-80}"

              # Colors (disabled if not a tty)
              if [ -t 1 ]; then
                GREEN=$'\x1b[32m'
                RED=$'\x1b[31m'
                RESET=$'\x1b[0m'
              else
                GREEN=""
                RED=""
                RESET=""
              fi

              # Extract short name from command for display
              get_lint_name() {
                local cmd="$1"
                # Extract first word (the command name)
                echo "$cmd" | awk '{print $1}' | sed 's|.*/||'
              }

              # Print result line with dots (pre-commit style)
              print_result() {
                local name="$1"
                local status="$2"
                local name_len="''${#name}"
                # Account for color codes in length calculation (Passed/Failed = 6 chars)
                local visible_status_len=6
                local dots_needed=$((term_width - name_len - visible_status_len - 1))
                [ "$dots_needed" -lt 3 ] && dots_needed=3
                local dots
                dots=$(printf '%*s' "$dots_needed" "" | tr ' ' '.')
                printf '%s%s%s\n' "$name" "$dots" "$status"
              }

              # Read lint commands from .jj-lint.toml (VCS-tracked) or fall back to repo config
              cmds=()
              repo_root="$(jj root 2>/dev/null || true)"
              lint_file="''${repo_root}/.jj-lint.toml"

              if [ -n "$repo_root" ] && [ -f "$lint_file" ]; then
                # Parse lints from TOML file using yj (converts TOML to JSON)
                while IFS= read -r cmd; do
                  [ -n "$cmd" ] && cmds+=("$cmd")
                done < <(yj -t < "$lint_file" | jq -r '.lints // empty | if type == "array" then .[] else empty end' 2>/dev/null || true)
              fi

              # Fall back to repo config if file doesn't exist or has no lints
              if [ ''${#cmds[@]} -eq 0 ]; then
                lints="$(jj config get dotfiles.push-lints 2>/dev/null || true)"
                if [ -n "$lints" ]; then
                  while IFS= read -r cmd; do
                    cmd="$(echo "$cmd" | xargs)"
                    [ -n "$cmd" ] && cmds+=("$cmd")
                  done < <(echo "$lints" | tr -d '[]"' | tr ',' '\n')
                fi
              fi

              if [ ''${#cmds[@]} -eq 0 ]; then
                echo "No lints configured (create .jj-lint.toml or set dotfiles.push-lints in repo config)"
                exit 0
              fi

              failed=0
              failed_cmds=()
              outputs=()

              for cmd in "''${cmds[@]}"; do
                name="$(get_lint_name "$cmd")"
                # Run command and capture output
                output=""
                if output=$(eval "$cmd" 2>&1); then
                  print_result "$name" "''${GREEN}Passed''${RESET}"
                else
                  print_result "$name" "''${RED}Failed''${RESET}"
                  failed=1
                  failed_cmds+=("$cmd")
                  outputs+=("$output")
                fi
              done

              # Print failure details at the end
              if [ "$failed" -eq 1 ]; then
                echo ""
                for i in "''${!failed_cmds[@]}"; do
                  echo "''${RED}==> ''${failed_cmds[$i]}''${RESET}"
                  echo "''${outputs[$i]}"
                  echo ""
                done
                exit 1
              fi
            '';
          };
        in ["util" "exec" "--" "${script}/bin/jj-lint"];

        # Complete workflow: finish current change and push to remote
        ship = with pkgs; let
          script = writeShellApplication {
            name = "jj-ship";
            runtimeInputs = [jujutsu coreutils gawk gnugrep];
            text = ''
              set -euo pipefail

              bookmark_input=""
              bookmark=""
              remote_ref=""
              push_args=()

              while [ "$#" -gt 0 ]; do
                case "$1" in
                  -b|--bookmark)
                    [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
                    bookmark_input="$2"
                    shift 2
                    ;;
                  --bookmark=*)
                    bookmark_input="''${1#*=}"
                    shift
                    ;;
                  --)
                    shift
                    push_args+=("$@")
                    break
                    ;;
                  *)
                    push_args+=("$1")
                    shift
                    ;;
                esac
              done

              has_changes=0
              if jj diff --summary --color=never | grep -q '[^[:space:]]'; then
                has_changes=1
              fi

              if [ "$has_changes" -eq 1 ]; then
                jj new
              fi

              target="@-"

              if [ -z "$bookmark_input" ]; then
                bookmark="$(jj log -r "heads(ancestors($target) & bookmarks())" -n 1 --no-graph --color=never -T "bookmarks" | awk '{print $1}')"
                if [ -z "$bookmark" ]; then
                  echo "No ancestor bookmark found. Use --bookmark <name> or create one with: jj bookmark set <name> -r $target" >&2
                  exit 1
                fi
                remote_ref="''${bookmark}@origin"
              else
                if echo "$bookmark_input" | grep -q '@'; then
                  bookmark="''${bookmark_input%@*}"
                  remote_ref="$bookmark_input"
                else
                  bookmark="$bookmark_input"
                  remote_ref="''${bookmark}@origin"
                fi
                if [ -z "$bookmark" ]; then
                  echo "Invalid bookmark value: $bookmark_input" >&2
                  exit 1
                fi
              fi

              target_id="$(jj log -r "$target" --no-graph --color=never -T "commit_id")"
              bookmark_id="$(jj log -r "$bookmark" --no-graph --color=never -T "commit_id" 2>/dev/null || true)"

              if [ -z "$bookmark_id" ] || [ "$bookmark_id" != "$target_id" ]; then
                jj bookmark set "$bookmark" -r "$target"
              fi

              if ! printf '%s\0' "''${push_args[@]}" | grep -q -- '--bookmark'; then
                push_args=(--bookmark "$bookmark" "''${push_args[@]}")
              fi

              if jj log -r "$remote_ref" --no-graph --color=never -T "commit_id" >/dev/null 2>&1; then
                if jj log -r "''${bookmark}..''${remote_ref}" -n 1 --no-graph --color=never -T "commit_id" | grep -q .; then
                  echo "Remote '$remote_ref' has new commits. Fetch and rebase before shipping:" >&2
                  echo "  jj git fetch && jj rebase -d ''${remote_ref}" >&2
                  exit 1
                fi

                if ! jj log -r "''${remote_ref}..''${bookmark}" -n 1 --no-graph --color=never -T "commit_id" | grep -q .; then
                  echo "Nothing to push for bookmark '$bookmark'." >&2
                  exit 0
                fi
              fi

              jj push "''${push_args[@]}"
            '';
          };
        in ["util" "exec" "--" "${script}/bin/jj-ship"];

        # Sync with upstream: fetch and rebase onto closest ancestor bookmark's remote
        sync = with pkgs; let
          script = writeShellApplication {
            name = "jj-sync";
            runtimeInputs = [jujutsu coreutils gawk gnugrep];
            text = ''
              set -euo pipefail

              bookmark_input=""
              bookmark=""
              remote_ref=""
              rebase_args=()

              while [ "$#" -gt 0 ]; do
                case "$1" in
                  -b|--bookmark)
                    [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
                    bookmark_input="$2"
                    shift 2
                    ;;
                  --bookmark=*)
                    bookmark_input="''${1#*=}"
                    shift
                    ;;
                  --)
                    shift
                    rebase_args+=("$@")
                    break
                    ;;
                  *)
                    rebase_args+=("$1")
                    shift
                    ;;
                esac
              done

              if [ -z "$bookmark_input" ]; then
                bookmark="$(jj log -r "heads(ancestors(@) & bookmarks())" -n 1 --no-graph --color=never -T "bookmarks" | awk '{print $1}')"
                if [ -z "$bookmark" ]; then
                  echo "No ancestor bookmark found. Use --bookmark <name> or create one with: jj bookmark set <name> -r @" >&2
                  exit 1
                fi
                remote_ref="''${bookmark}@origin"
              else
                if echo "$bookmark_input" | grep -q '@'; then
                  bookmark="''${bookmark_input%@*}"
                  remote_ref="$bookmark_input"
                else
                  bookmark="$bookmark_input"
                  remote_ref="''${bookmark}@origin"
                fi
                if [ -z "$bookmark" ]; then
                  echo "Invalid bookmark value: $bookmark_input" >&2
                  exit 1
                fi
              fi

              remote="origin"
              if echo "$remote_ref" | grep -q '@'; then
                remote="''${remote_ref#*@}"
              fi

              jj git fetch "$remote"

              if ! jj log -r "$remote_ref" --no-graph --color=never -T "commit_id" >/dev/null 2>&1; then
                echo "Remote ref '$remote_ref' not found after fetch." >&2
                exit 1
              fi

              jj rebase -d "$remote_ref" "''${rebase_args[@]}"
            '';
          };
        in ["util" "exec" "--" "${script}/bin/jj-sync"];

        # Push with pre-push lints (configurable per-repo)
        # Or skip lints entirely with: jj git push
        # Configure lints in .jj-lint.toml (VCS-tracked) or repo config (.jj/repo/config.toml)
        push = with pkgs; let
          script = writeShellApplication {
            name = "jj-push";
            runtimeInputs = [jujutsu coreutils fd shellcheck alejandra statix gnused yj jq];
            text = ''
              set -euo pipefail

              # Terminal width for formatting (default 80)
              term_width="''${COLUMNS:-80}"

              # Colors (disabled if not a tty)
              if [ -t 1 ]; then
                GREEN=$'\x1b[32m'
                RED=$'\x1b[31m'
                RESET=$'\x1b[0m'
              else
                GREEN=""
                RED=""
                RESET=""
              fi

              # Extract short name from command for display
              get_lint_name() {
                local cmd="$1"
                echo "$cmd" | awk '{print $1}' | sed 's|.*/||'
              }

              # Print result line with dots (pre-commit style)
              print_result() {
                local name="$1"
                local status="$2"
                local name_len="''${#name}"
                local visible_status_len=6
                local dots_needed=$((term_width - name_len - visible_status_len - 1))
                [ "$dots_needed" -lt 3 ] && dots_needed=3
                local dots
                dots=$(printf '%*s' "$dots_needed" "" | tr ' ' '.')
                printf '%s%s%s\n' "$name" "$dots" "$status"
              }

              # Read lint commands from .jj-lint.toml (VCS-tracked) or fall back to repo config
              cmds=()
              repo_root="$(jj root 2>/dev/null || true)"
              lint_file="''${repo_root}/.jj-lint.toml"

              if [ -n "$repo_root" ] && [ -f "$lint_file" ]; then
                # Parse lints from TOML file using yj (converts TOML to JSON)
                while IFS= read -r cmd; do
                  [ -n "$cmd" ] && cmds+=("$cmd")
                done < <(yj -t < "$lint_file" | jq -r '.lints // empty | if type == "array" then .[] else empty end' 2>/dev/null || true)
              fi

              # Fall back to repo config if file doesn't exist or has no lints
              if [ ''${#cmds[@]} -eq 0 ]; then
                lints="$(jj config get dotfiles.push-lints 2>/dev/null || true)"
                if [ -z "$lints" ]; then
                  echo "No push lints configured (create .jj-lint.toml or set dotfiles.push-lints in repo config)"
                  jj git push "$@"
                  exit 0
                fi
                while IFS= read -r cmd; do
                  cmd="$(echo "$cmd" | xargs)"
                  [ -n "$cmd" ] && cmds+=("$cmd")
                done < <(echo "$lints" | tr -d '[]"' | tr ',' '\n')
              fi

              if [ ''${#cmds[@]} -eq 0 ]; then
                jj git push "$@"
                exit 0
              fi

              failed=0
              failed_cmds=()
              outputs=()

              for cmd in "''${cmds[@]}"; do
                name="$(get_lint_name "$cmd")"
                output=""
                if output=$(eval "$cmd" 2>&1); then
                  print_result "$name" "''${GREEN}Passed''${RESET}"
                else
                  print_result "$name" "''${RED}Failed''${RESET}"
                  failed=1
                  failed_cmds+=("$cmd")
                  outputs+=("$output")
                fi
              done

              # Print failure details at the end
              if [ "$failed" -eq 1 ]; then
                echo ""
                for i in "''${!failed_cmds[@]}"; do
                  echo "''${RED}==> ''${failed_cmds[$i]}''${RESET}"
                  echo "''${outputs[$i]}"
                  echo ""
                done
                exit 1
              fi

              echo ""
              echo "Lints passed! Pushing..."
              jj git push "$@"
            '';
          };
        in ["util" "exec" "--" "${script}/bin/jj-push"];
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
