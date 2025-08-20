{...}: {
  programs.gitui = {
    keyConfig = builtins.readFile ./keybindings.ron;
  };
}
