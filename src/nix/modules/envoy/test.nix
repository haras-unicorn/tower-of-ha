{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-proxy-envoy = selfLib.test.contract.implementation {
    capability = "proxy";
    implementation = "envoy";
    server = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
    };
    # NOTE: the stats port lets other machines reach the admin interface,
    # which can also change and stop the proxy, so only the stats and the
    # health path go through; checked in the routing test only, since the
    # balancing variants have the same listener
    test =
      { config, machines, ... }:
      let
        server = machines.server1;
        statsUrl = "http://${server.toh.meta.network.ip}:${builtins.toString server.toh.services.envoy.statsPort}";
        closedPaths = [
          "/stats"
          "/config_dump"
          "/clusters"
          "/runtime"
        ];
        closedPosts = [
          "/quitquitquit"
          "/runtime_modify?key=value"
          "/logging?level=trace"
          "/healthcheck/fail"
          "/drain_listeners"
        ];
      in
      {
        toh.test.commands.suffix =
          if config.toh.test.contracts.proxy.balancing == null then
            ''
              client.wait_until_succeeds("curl --silent --fail ${statsUrl}/stats/prometheus", timeout=60)
              ${builtins.concatStringsSep "\n" (
                builtins.map (path: ''client.fail("curl --silent --fail ${statsUrl}${path}")'') closedPaths
                ++ builtins.map (
                  path: ''client.fail("curl --silent --fail --request POST '${statsUrl}${path}'")''
                ) closedPosts
              )}
              client.succeed("curl --silent --fail ${statsUrl}/stats/prometheus")
            ''
          else
            "";
      };
  };

  self.nixosTests = selfLib.test.proxyTests "envoy";
}
