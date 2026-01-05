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
      signing = {
        inherit (config.programs.git.signing) key;
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
