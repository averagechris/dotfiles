{...}: {
  programs.lazygit.settings = {
    keybinding = {
      universal = {
        prevItem = "<up>";
        prevItem-alt = "e";
        nextItem = "<down>";
        nextItem-alt = "n";
        scrollLeft = "m";
        scrollRight = "i";
        prevBlock-alt = "E";
        nextBlock-alt = "N";
        nextMatch = "k";
        prevMatch = "K";
        new = "<c-n>";
        edit = "<c-e>";
        openFile = "<c-o>";
        # scrollUpMain-alt1 = "E";
        # scrollDownMain-alt1 = "N";
        executeShellCommand = "!";
        createRebaseOptionsMenu = "<c-r>";
        pushFiles = "P";
        pullFiles = "p";
        refresh = "R";
        createPatchOptionsMenu = "<c-p>";
        undo = "u";
        redo = "U";
        copyToClipboard = "y";
      };
      status = {
        checkForUpdate = "r";
      };
      files = {
        ignoreFile = "I";
      };
      commits = {
        moveDownCommit = "<c-n>";
        moveUpCommit = "<c-e>";
      };
    };
  };
}
