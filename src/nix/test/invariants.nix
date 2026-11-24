# NOTE: every test checks the invariants of the design that can be checked on
# its machines: the ones about the nix code before it runs, the ones about the
# running machines after its own commands, when its services are up

{
  self.lib.test.testModules.invariants =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.invariants;

      firewallOf =
        machine:
        let
          firewall = machine.networking.firewall;

          rules = [ firewall ] ++ builtins.attrValues firewall.interfaces;

          rangesOf =
            name:
            builtins.map (range: [
              range.from
              range.to
            ]) (builtins.concatMap (rule: rule.${name}) rules);
        in
        {
          tcp = builtins.concatMap (rule: rule.allowedTCPPorts) rules;
          udp = builtins.concatMap (rule: rule.allowedUDPPorts) rules;
          tcpRanges = rangesOf "allowedTCPPortRanges";
          udpRanges = rangesOf "allowedUDPPortRanges";
        };

      privateOf =
        machine:
        lib.filterAttrs (name: _: !(machine.toh.meta.sops.secrets.${name}.public or false)) (
          machine.sops.secrets // machine.sops.templates
        );

      secretPathsOf =
        machine: builtins.map (secret: secret.path) (builtins.attrValues (privateOf machine));

      perMachine = check: builtins.concatStringsSep "\n" (lib.mapAttrsToList check machines);
    in
    {
      options.toh.test.invariants = {
        free.enable = (lib.mkEnableOption "the check that nixpkgs refuses unfree packages") // {
          default = true;
        };

        secrets.enable = (lib.mkEnableOption "the check that no secret is open to other users") // {
          default = true;
        };

        ports.enable =
          (lib.mkEnableOption "the check that every port open to the network is open in the firewall")
          // {
            default = true;
          };
      };

      config = {
        defaults =
          { config, pkgs, ... }:
          let
            # NOTE: what the machine sets, because nixpkgs may give the
            # predicate and the lists defaults of its own
            nixpkgsSettings = config.nixpkgs.config;

            secrets = lib.mapAttrsToList (name: secret: {
              inherit name;
              inherit (secret) mode;
            }) (privateOf config);

            # NOTE: the last digit of a mode is what every other user may do
            openToOthers = secret: lib.last (lib.stringToCharacters secret.mode) != "0";
          in
          {
            assertions = [
              {
                assertion =
                  !cfg.free.enable
                  || !(
                    (pkgs.config.allowUnfree or false)
                    || nixpkgsSettings ? allowUnfreePredicate
                    || nixpkgsSettings ? allowlistedLicenses
                    || nixpkgsSettings ? whitelistedLicenses
                  );
                message = ''
                  Invariant 1: nixpkgs of ${config.toh.meta.machine.name} lets unfree
                  packages through.
                '';
              }
              {
                assertion = !cfg.secrets.enable || !(builtins.any openToOthers secrets);
                message = ''
                  Secret permissions: other users may read these secrets on
                  ${config.toh.meta.machine.name}: ${
                    builtins.concatStringsSep ", " (
                      builtins.map (secret: "${secret.name} (${secret.mode})") (builtins.filter openToOthers secrets)
                    )
                  }.
                '';
              }
            ];
          };

        toh.test.commands.checks = [
          ''
            import ipaddress
            import json

            invariant_findings = []

            def invariant_found(name, text):
              invariant_findings.append(f"{name}: {text}")
          ''

          (lib.optionalString cfg.secrets.enable ''
            def check_secrets(machine, name, paths):
              if not paths:
                return
              quoted = " ".join(f"'{path}'" for path in paths)
              # NOTE: a secret may be gone on purpose, like the age key that
              # is shredded after its use, so missing paths are left out
              _, output = machine.execute(
                f"find -L {quoted} -maxdepth 0 -perm /o=rwx 2>/dev/null"
              )
              for path in output.split():
                invariant_found(name, f"other users may use the secret {path}")

            ${perMachine (
              name: machine:
              "check_secrets(${name}, '${name}', json.loads('${builtins.toJSON (secretPathsOf machine)}'))"
            )}
          '')

          (lib.optionalString cfg.ports.enable ''
            def listener_address(local):
              address, _, port = local.rpartition(":")
              address = address.strip("[]").split("%")[0]
              return address, int(port)

            def is_loopback(address):
              if address == "*":
                return False
              ip = ipaddress.ip_address(address)
              mapped = getattr(ip, "ipv4_mapped", None)
              return (mapped or ip).is_loopback

            def check_ports(machine, name, firewall):
              low, high = (
                int(port)
                for port in machine.succeed("cat /proc/sys/net/ipv4/ip_local_port_range").split()
              )
              listeners = machine.succeed(
                "ss --listening --numeric --tcp --udp --processes --no-header"
              )
              for line in listeners.splitlines():
                fields = line.split()
                protocol = fields[0]
                address, port = listener_address(fields[4])
                if is_loopback(address):
                  continue
                # NOTE: udp clients bind ports of the ephemeral range to get
                # their answers, and these show up like listeners
                if protocol == "udp" and low <= port <= high:
                  continue
                ports = firewall[protocol]
                ranges = firewall[f"{protocol}Ranges"]
                if port in ports or any(start <= port <= end for start, end in ranges):
                  continue
                process = " ".join(fields[6:])
                invariant_found(
                  name,
                  f"{protocol} {address}:{port} listens but is not open in the firewall {process}",
                )

            ${perMachine (
              name: machine:
              "check_ports(${name}, '${name}', json.loads('${builtins.toJSON (firewallOf machine)}'))"
            )}
          '')

          ''
            assert not invariant_findings, "Invariants broken:\n" + "\n".join(invariant_findings)
          ''
        ];
      };
    };
}
