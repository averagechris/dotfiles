{ pgks, ... }:
{
  programs.git = {
    enable = true;
    extraConfig = { pull.rebase = true; };
    # these are be defined in localhome.default.nix
    # userName
    # userEmail
  };
}
