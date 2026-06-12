{
  toh.lib.garage = {
    certs = {
      root = "/etc/garage/certs";
      user = "~/.garage/certs";
      keyId = "id.txt";
      secretKey = "secret.txt";
    };

    defaultUser = {
      user = "garage";
      group = "garage";
    };
  };
}
