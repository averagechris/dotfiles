{ pgks, ... }:
{
  programs.git = {
    enable = true;
    delta.enable = true;
    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
    };
    ignores = [ ".DS_Store" ];
    # these are be defined in the nixos user definition
    # userName
    # userEmail
  };
}
