##################################################
##################################################
##################################################
##################################################
#
# use this as an example for localhome/default.nix
#
##################################################
##################################################
##################################################
##################################################
##################################################

{config, pgks, ...}:

{
  # import whatever modules you want on this system
  imports = [ ../doom ../email ../python ../neovim ../tmux ../shell ../rust ];

  home.username = "your_user_name";
  home.homeDirectory = "/home/chris";
  home.stateVersion = "21.03";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "My full name";
    userEmail = "email@email.com";
    extraConfig = { pull.rebase = true; };
  };
}
