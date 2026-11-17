{
  toh.lib.garage = {
    certs = {
      root = "/etc/garage/certs";
      user = "~/.garage/certs";
      keyId = "id.txt";
      secretKey = "secret.txt";
    };

    user = "garage";
    group = "garage";
  };
}
