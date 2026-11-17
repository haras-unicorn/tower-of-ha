{
  toh.lib.email = {
    makeAddress =
      {
        name,
        host,
        port ? null,
      }:
      if port == null then "${name}@${host}" else "${name}@${host}:${builtins.toString port}";
  };
}
