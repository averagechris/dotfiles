{ pgks, ... }:
{
  programs.git = {
    enable = true;
    delta.enable = true;
    extraConfig = { pull.rebase = true; };
    ignores = [ ".DS_Store" ];
    # these are be defined in localhome.default.nix
    # userName
    # userEmail
  };
}
