{
  toh.lib.secrets = {
    directories = {
      cluster = "$out/cluster";
      machines = "$out/machines";
      external = "$out/external";
    };

    keys = {
      mount = "kv";
      cluster = "toh/cluster";
      machines = "toh/machines";
      external = "toh/external";
      root = "toh/root";
      age = "age-private";
    };

    files = {
      token = "token.txt";
      response = "response.txt";
      metadata = "metadata.json";
      root = "root.json";
    };
  };
}
