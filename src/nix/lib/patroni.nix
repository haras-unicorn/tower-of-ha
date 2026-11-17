{
  toh.lib.patroni = {
    env = "user.env";
    url = "user.url";
    password = "user.txt";
    certs = {
      root = "/etc/postgresql/certs";
      user = "~/.postgresql/certs";
      ca = "ca.crt";
      crt = "user.crt";
      key = "user.key";
    };
    superusers = {
      superuser = "postgres";
      replication = "replicator";
      rewind = "rewinder";
    };
  };
}
