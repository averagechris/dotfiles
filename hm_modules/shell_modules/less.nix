{...}: {
  programs.less = {
    enable = true;
    keys = ''
      n forw-line
      e back-line
      i right-scroll
      h left-scroll
      k repeat-search
      K reverse-search
      h set-mark
      H goto-mark
      \e undo-hilite
    '';
  };
  programs.lesspipe.enable = true;
}
