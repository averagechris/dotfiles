you have to symlink the layer into ~/.emacs.d/private/
then add the name of the layer into `~/.spacemacs` in `dotspacemacs-configuration-layers`
like this:
```
   dotspacemacs-configuration-layers
   '(
     personal-layer
    ... a bunch of stuff already here and comments
    )
```

NOTE: we do not sync the .spacemacs file with vcs cause it's a pain in the ass and stores a lot of state.
Just init emacs for the first time, choose the basic normal settings, add the layer then restart emacs.
