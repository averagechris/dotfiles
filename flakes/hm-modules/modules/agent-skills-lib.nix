{lib}: let
  discoverBundle = bundle:
    if bundle.sourceDirectory == null
    then []
    else let
      entries = builtins.readDir bundle.sourceDirectory;
    in
      lib.sort builtins.lessThan (
        if bundle.layout == "directories"
        then
          lib.filter
          (name:
            entries.${name}
            == "directory"
            && builtins.pathExists (bundle.sourceDirectory + "/${name}/SKILL.md"))
          (builtins.attrNames entries)
        else
          map
          (name: lib.removeSuffix ".md" name)
          (lib.filter
            (name: entries.${name} != "directory" && lib.hasSuffix ".md" name)
            (builtins.attrNames entries))
      );
in {
  inherit discoverBundle;

  auditBundle = bundle: let
    expected = lib.sort builtins.lessThan bundle.expectedNames;
    discovered = discoverBundle bundle;
  in {
    inherit discovered expected;
    added = lib.subtractLists expected discovered;
    removed = lib.subtractLists discovered expected;
    matches = discovered == expected;
  };
}
