{ lib, tohLib, ... }:

{
  toh.lib.lists = {
    uniqueBy =
      predicate: list:
      builtins.foldl' (
        acc: next:
        if builtins.any (prev: (predicate prev) == (predicate next)) acc then acc else acc ++ [ next ]
      ) [ ] list;

    concatUniqueAttrValues = tohLib.lists.concatMapUniqueAttrValues ({ value, ... }: value);

    concatMapUniqueAttrValues =
      predicate: listOfAttrs:
      builtins.map predicate (
        tohLib.lists.uniqueBy ({ name, ... }: name) (builtins.concatMap lib.attrsToList listOfAttrs)
      );
  };
}
