{
  toh.lib.secrets = {
    directories = {
      cluster = "$out/cluster";
      machines = "$out";
      external = "$out/external";
    };

    keys = {
      cluster = "kv/toh/cluster";
      machines = "kv/toh/machines";
      external = "kv/toh/external";
    };
  };
}
