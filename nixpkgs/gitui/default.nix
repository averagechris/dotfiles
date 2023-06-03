{...}: {
  programs.gitui = {
    enable = true;
    keyConfig = builtins.readFile ./keybindings.ron;
  };
}
