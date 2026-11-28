{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-oidc-authelia = selfLib.test.contract.implementation {
    capability = "oidc";
    implementation = "authelia";
    server = {
      toh.programs.cli.enable = true;
      toh.services.envoy.enable = true;
      toh.services.coredns.enable = true;
      toh.services.etcd.enable = true;
      toh.services.patroni.enable = true;
      toh.services.valkey.enable = true;
      toh.services.lldap.enable = true;
      toh.services.garage.enable = true;
      toh.services.maddy.enable = true;
      toh.services.authelia.enable = true;
    };
    # NOTE: the clients are in Patroni and the sessions in Valkey
    test.toh.test.contracts.oidc.redundant =
      "${selfLib.test.redundant.patroni} && ${selfLib.test.redundant.valkey}";
  };

  self.lib.test.faultTests.contracts-oidc-authelia = {
    toh.test.contracts.oidc = {
      enable = true;
      implementation.authelia = { };
    };
  };

  self.nixosTests.services-authelia = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.clusters.node = {
      amount = 3;
      module =
        { config, ... }:
        {
          toh.programs.cli.enable = true;
          toh.services.envoy.enable = true;
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

    # NOTE: Authelia's own API logs a user in without a browser; the session
    # is in Valkey, so a login on one machine holds on every machine, and a
    # wrong password comes last, since Authelia bans a user after a few
    toh.test.commands.suffix = ''
      node1.succeed("toh ldap user add tester testpass123 tester@email.service.toh --display-name tester")
      session = node1.wait_until_succeeds("""
        curl -f -o /dev/null -c - \
          -H 'Content-Type: application/json' \
          -d '{"username":"tester","password":"testpass123"}' \
          https://authelia.service.toh/api/firstfactor \
          | awk '$6 == "authelia_session" { print $7 }' | grep .
      """, timeout=60).strip()
      for node in [node1, node2, node3]:
        node.succeed(f"""
          curl -f -b 'authelia_session={session}' \
            https://authelia.service.toh/api/user/info \
            | grep -q '"display_name":"tester"'
        """)
      output = node1.succeed("""
        curl -s -o /dev/null -w '%{http_code}' \
          -H 'Content-Type: application/json' \
          -d '{"username":"tester","password":"wrong"}' \
          https://authelia.service.toh/api/firstfactor
      """)
      assert output == "401", output
    '';
  };
}
