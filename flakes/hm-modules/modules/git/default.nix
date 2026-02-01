{
  config,
  pkgs,
  lib,
  ...
}: {
  config.home.packages = [pkgs.gnupg];
  config.programs.git = {
    # Note: The gpg module (flakes/hm-modules/modules/gpg.nix) manages git config
    # including signing.key when dotfiles.gpg.enable = true. It imports the GPG key
    # from agenix and configures signing during activation.
    settings = {
      pull.rebase = true;
      init.defaultBranch = "main";
    };
    ignores = [".DS_Store"];
    # signing configuration is managed by the gpg module when enabled

    settings.alias = with pkgs; {
      ch = let
        name = "git_alias_chbranch";
      in "!${writeShellApplication {
        inherit name;
        runtimeInputs = [git gnugrep findutils fzf];
        text = ''
          git branch --list \
            | grep --invert-match --regexp '^* ' \
            | fzf --query "''${*:-}" --exit-0 --select-1 \
            | xargs git switch
        '';
      }}/bin/${name}";

      del = let
        name = "git_alias_delete_branches";
      in "!${writeShellApplication {
        inherit name;
        runtimeInputs = [git findutils fzf];
        text = ''
          BRANCHES="$$(
            git branch --list \
              | grep --invert-match --regexp '^* ' \
              | fzf --multi
          )"

          for branch in $BRANCHES; do
              git branch -D "$branch"
          done

          if [[ "$1" == "-r" || "$1" == "--remote" ]]; then
              git push origin --delete "$BRANCHES"
          fi
        '';
      }}/bin/${name}";

      ui = "!${config.programs.lazygit.package}/bin/lazygit";
    };
  };
  config.programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}
