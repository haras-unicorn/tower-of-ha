{ lib, ... }:

let
  uniqueBy =
    predicate: list:
    builtins.foldl' (
      acc: next:
      if builtins.any (prev: (predicate prev) == (predicate next)) acc then acc else acc ++ [ next ]
    ) [ ] list;

  concatMapUniqueAttrValues =
    predicate: listOfAttrs:
    builtins.map predicate (
      uniqueBy ({ name, ... }: name) (builtins.concatMap lib.attrsToList listOfAttrs)
    );

  concatUniqueAttrValues = concatMapUniqueAttrValues ({ value, ... }: value);
in
{
  self.lib.lists = {
    inherit uniqueBy concatMapUniqueAttrValues concatUniqueAttrValues;
  };
}
