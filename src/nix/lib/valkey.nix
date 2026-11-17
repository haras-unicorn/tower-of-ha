{
  toh.lib.valkey = {
    env = "user.env";
    url = "user.url";
    password = "user.txt";
    certs = {
      root = "/etc/valkey/certs";
      user = "~/.valkey/certs";
      ca = "ca.crt";
      crt = "user.crt";
      key = "user.key";
    };
    users = {
      default = "default";
      superuser = "valkey";
      master = "master";
      sentinel = "sentinel";
    };
  };
}
