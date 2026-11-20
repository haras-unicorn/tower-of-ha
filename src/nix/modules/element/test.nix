{ selfLib, ... }:

{
  self.nixosTests.services-element = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.haproxy.enable = true;
        toh.services.element.enable = true;

        # NOTE: Element only needs the address of the chat, so the test gives
        # it one instead of running Synapse
        toh.meta.chat.host = "synapse.service.toh";
      };
    };

    toh.test.commands.prefix = "import json";

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_for_unit("static-web-server.socket")''
      ''command_node.wait_until_succeeds("curl -sf https://element.service.toh/health", timeout=120)''
      ''command_node.succeed("curl -sf https://element.service.toh/ | grep -F '<title>Element</title>' > /dev/null")''
      (node: ''
        config = json.loads(command_node.succeed("curl -sf https://element.service.toh/config.json"))
        base_url = config["default_server_config"]["m.homeserver"]["base_url"]
        assert base_url == "${node.toh.meta.chat.url}", base_url
        assert config["integrations_ui_url"] is None, config["integrations_ui_url"]
      '')
    ];
  };
}
