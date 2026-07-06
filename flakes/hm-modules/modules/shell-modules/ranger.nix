{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  ...
}: let
  cfg = config.dotfiles.shell.ranger;
in {
  options.dotfiles.shell.ranger = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables ranger, the tui file manager.";
  };
  config = lib.mkIf (config.dotfiles.shell.enable && cfg.enable) {
    home.packages = [pkgs.ranger];
    xdg.configFile = lib.mkIf cfg.enable {
      "ranger/rc.conf".text = ''
        map l display_file
        map <A-n> scroll_preview 1
        map <A-e> scroll_preview -1

        copymap <UP> e
        copymap <DOWN> n
        copymap <LEFT> m
        copymap <RIGHT> i

        map N move down=0.5  pages=True
        map E move up=0.5    pages=True
        copymap N <C-D>
        copymap E <C-U>

        map M history_go -1
        map I history_go 1
        map ] move_parent 1

        map L eval fm.open_console('rename ' + fm.thisfile.relative_path.replace("%", "%%"), position=7)
        map <C-n> search_next
        map <C-N> search_next forward=False

        tmap N eval -q fm.ui.taskview.task_move(-1)
        tmap E eval -q fm.ui.taskview.task_move(0)
      '';
    };
  };
}
