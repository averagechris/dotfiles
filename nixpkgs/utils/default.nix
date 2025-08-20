{pkgs, ...}: {
  mkINI = pkgs.lib.generators.toINI {
    mkKeyValue = key: value: let
      v =
        if pkgs.lib.isBool value
        then
          (
            if value
            then "True"
            else "False"
          )
        else toString value;
    in "${key} = ${v}";
  };
}
