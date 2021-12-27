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
    , mkValue ? (v: pkgs.lib.generators.mkValueStringDefault { } v)
    ,
    }: attrs:
    (pkgs.lib.strings.concatStringsSep
      "\n"
      (pkgs.lib.attrsets.mapAttrsToList
        (key: value: "${mkKey key} ${mkValue value}")
        attrs));
}
