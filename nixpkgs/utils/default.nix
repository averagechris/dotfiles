{ pkgs, ... }:
{

  mkINI = pkgs.lib.generators.toINI {
    mkKeyValue = key: value:
      let
        v =
          if pkgs.lib.isBool value then
            (if value then "True" else "False")
          else toString value;
      in
      "${key} = ${v}";
  };

  stringify =
    { mkKey ? (k: "${k}")
    , mkValue ? pkgs.lib.generators.mkValueStringDefault
    ,
    }: attrs:
    (pkgs.lib.strings.concatStringsSep
      "\n"
      (pkgs.lib.attrsets.mapAttrsToList
        (key: value: "${mkKey key} ${mkValue value}")
        attrs));
}
