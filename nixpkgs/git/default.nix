{pkgs, ...}: {
  programs.git = {
    enable = true;
    delta.enable = true;
    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
    };
    ignores = [".DS_Store"];
    # these are be defined in the nixos user definition
    # userName
    # userEmail

    aliases = with pkgs; {
      ch = let
        name = "git_alias_chbranch";
      in "!${writeShellApplication {
        inherit name;
        runtimeInputs = [git gnugrep findutils fzf];
        text = ''
          git branch --list \
            | grep --invert-match --regexp '^* ' \
            | fzf --exit-0 --select-1 \
            | xargs git checkout
        '';
      }}/bin/${name}";

      del = let
        name = "git_alias_delete_branches";
      in "!${writeShellApplication {
        inherit name;
        runtimeInputs = [git findutils fzf];
        text = ''
          git branch --list \
            | grep --invert-match --regexp '^* ' \
            | fzf --multi \
            | xargs git branch -D
        '';
      }}/bin/${name}";
    };
  };
}
