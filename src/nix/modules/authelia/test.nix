{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-oidc-authelia = selfLib.test.contract.implementation {
    capability = "oidc";
    implementation = "authelia";
    server = {
      toh.services.haproxy.enable = true;
      toh.services.coredns.enable = true;
      toh.services.etcd.enable = true;
      toh.services.patroni.enable = true;
      toh.services.valkey.enable = true;
      toh.services.lldap.enable = true;
      toh.services.garage.enable = true;
      toh.services.maddy.enable = true;
      toh.services.authelia.enable = true;
    };
  };

  self.nixosTests.contracts-oidc-authelia = selfLib.test.makeNixosTest {
    toh.test.contracts.oidc = {
      enable = true;
      implementation.authelia = { };
    };
  };

  self.nixosTests.services-authelia = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module =
        { config, ... }:
        {
          toh.programs.cli.enable = true;
          toh.services.haproxy.enable = true;
          toh.services.coredns.enable = true;
          toh.services.etcd.enable = true;
          toh.services.patroni.enable = true;
          toh.services.valkey.enable = true;
          toh.services.lldap.enable = true;
          toh.services.garage.enable = true;
          toh.services.maddy.enable = true;
          toh.services.authelia.enable = true;
          toh.meta.oidc.apps.test = {
            user = "test";
            group = "test";
            redirectUris = [ "https://${config.toh.meta.machine.name}.${config.toh.meta.domains.node}" ];
          };
        };
    };

    toh.test.commands.perNode = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-oidc-online.target", timeout=300)''
      ''
        command_node.wait_until_succeeds("""
          curl -f https://authelia.service.toh/api/health | grep -q '"status":"OK"'
        """, timeout=60)
      ''
    ];
  };
}
