{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib, ... }:
{

  isNixOS = lib.hasInfix "NAME=NixOS" (builtins.readFile /etc/os-release);
  mkINI = lib.generators.toINI {
    mkKeyValue = key: value:
      let
        v =
          if lib.isBool value then
            (if value then "True" else "False")
          else toString value;
      in
      "${key} = ${v}";
  };

  stringify =
    { mkKey ? (k: "${k}")
    , mkValue ? (v: lib.generators.mkValueStringDefault { } v)
    ,
    }: attrs:
    (lib.strings.concatStringsSep
      "\n"
      (lib.attrsets.mapAttrsToList
        (key: value: "${mkKey key} ${mkValue value}")
        attrs));
}
