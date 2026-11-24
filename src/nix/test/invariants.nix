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
          inherit (machine.toh.meta.network) holePunchers;
        };

      privateOf =
        machine:
        lib.filterAttrs (name: _: !(machine.toh.meta.sops.secrets.${name}.public or false)) (
          machine.sops.secrets // machine.sops.templates
        );

      secretPathsOf =
        machine: builtins.map (secret: secret.path) (builtins.attrValues (privateOf machine));

      # NOTE: templates are left out, because the rest of a template is
      # config that the store holds too
      privateSecretPathsOf =
        machine:
        builtins.map (secret: secret.path) (
          builtins.attrValues (
            lib.filterAttrs (
              name: _: !(machine.toh.meta.sops.secrets.${name}.public or false)
            ) machine.sops.secrets
          )
        );

      sopsKeysOf =
        machine:
        builtins.map (secret: secret.key) (
          builtins.filter (secret: secret.sopsFile == machine.sops.defaultSopsFile) (
            builtins.attrValues machine.sops.secrets
          )
        );

      publicKeysOf =
        machine:
        builtins.map (secret: secret.key) (
          builtins.attrValues (
            lib.filterAttrs (
              name: _: machine.toh.meta.sops.secrets.${name}.public or false
            ) machine.sops.secrets
          )
        );

      closure = config.hostPkgs.closureInfo {
        rootPaths = lib.mapAttrsToList (_: machine: machine.system.build.toplevel) machines;
      };

      openssl = lib.getExe config.hostPkgs.openssl;

      # NOTE: the test driver names the python variable of a machine like
      # the machine, with dashes and dots turned into underscores
      pythonName = builtins.replaceStrings [ "-" "." ] [ "_" "_" ];

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

        sops = {
          enable = (lib.mkEnableOption "the check that secrets live only in sops") // {
            default = true;
          };

          minimumLength = lib.mkOption {
            type = lib.types.ints.positive;
            default = 16;
            description = ''
              The length a line of a secret needs before the check looks for
              it in the store, because shorter lines turn up by chance
            '';
          };
        };

        leastPrivilege = {
          enable =
            (lib.mkEnableOption "the check that the sops file of a machine holds only what it uses")
            // {
              default = true;
            };

          strict = lib.mkEnableOption ''
            failing the test on what the machine made on its way to its own
            secrets, and not only showing it in the log; a secret of another
            machine always fails it
          '';
        };

        tls = {
          enable = (lib.mkEnableOption "the check that every port open to the network speaks TLS") // {
            default = true;
          };

          strict = lib.mkEnableOption "failing the test on a port without TLS, and not only showing it in the log";

          timeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "Seconds the check gives a port to answer a TLS handshake";
          };
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
            # NOTE: under names of their own, because the test commands may
            # import the same modules, and the linter refuses that twice
            import ipaddress as invariant_ipaddress
            import json as invariant_json
            import re as invariant_re
            import subprocess as invariant_subprocess

            invariant_findings = []
            invariant_warnings = []

            def invariant_found(name, text):
              invariant_findings.append(f"{name}: {text}")

            def invariant_warned(name, text):
              invariant_warnings.append(f"{name}: {text}")

            # NOTE: both protocols every time, because ss leaves out the
            # column of the protocol when it is asked about only one
            def network_listeners(machine):
              listeners = machine.succeed(
                "ss --listening --numeric --tcp --udp --processes --no-header"
              )
              for line in listeners.splitlines():
                fields = line.split()
                address, _, port = fields[4].rpartition(":")
                address = address.strip("[]").split("%")[0]
                if address != "*":
                  ip = invariant_ipaddress.ip_address(address)
                  mapped = getattr(ip, "ipv4_mapped", None)
                  if (mapped or ip).is_loopback:
                    continue
                yield fields[0], address, int(port), " ".join(fields[6:])
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
              "check_secrets(${pythonName name}, '${name}', invariant_json.loads('${builtins.toJSON (secretPathsOf machine)}'))"
            )}
          '')

          (lib.optionalString cfg.ports.enable ''
            def check_ports(machine, name, firewall):
              low, high = (
                int(port)
                for port in machine.succeed("cat /proc/sys/net/ipv4/ip_local_port_range").split()
              )
              for protocol, address, port, process in network_listeners(machine):
                # NOTE: udp clients bind ports of the ephemeral range to get
                # their answers, and these show up like listeners
                if protocol == "udp" and low <= port <= high:
                  continue
                processes = invariant_re.findall(r'"([^"]+)"', process)
                if protocol == "udp" and any(
                  punching in firewall["holePunchers"] for punching in processes
                ):
                  continue
                ports = firewall[protocol]
                ranges = firewall[f"{protocol}Ranges"]
                if port in ports or any(start <= port <= end for start, end in ranges):
                  continue
                invariant_found(
                  name,
                  f"{protocol} {address}:{port} listens but is not open in the firewall {process}",
                )

            ${perMachine (
              name: machine:
              "check_ports(${pythonName name}, '${name}', invariant_json.loads('${builtins.toJSON (firewallOf machine)}'))"
            )}
          '')

          (lib.optionalString cfg.sops.enable ''
            # NOTE: invariant 2, as far as a test sees it: no secret made
            # from sops ends up in the store, outside of the sops files
            invariant_secret_lines = {}

            def collect_secrets(machine, name, paths):
              for path in paths:
                status, content = machine.execute(f"cat '{path}'")
                if status != 0:
                  continue
                lines = [line.strip() for line in content.splitlines()]
                line = max(lines, key=len, default="")
                if len(line) >= ${builtins.toString cfg.sops.minimumLength}:
                  invariant_secret_lines[line] = f"{name}: {path}"

            ${perMachine (
              name: machine:
              "collect_secrets(${pythonName name}, '${name}', invariant_json.loads('${builtins.toJSON (privateSecretPathsOf machine)}'))"
            )}

            if invariant_secret_lines:
              with open("${closure}/store-paths") as store_paths:
                searched = [
                  path.strip()
                  for path in store_paths
                  if path.strip() != "${config.cryl.sops.package}"
                ]
              found = invariant_subprocess.run(
                ["grep", "--recursive", "--fixed-strings", "--text",
                 "--only-matching", "--null", "--file=-", *searched],
                input="\n".join(invariant_secret_lines).encode(),
                capture_output=True,
              )
              # NOTE: grep says 1 when nothing matches and 2 on errors
              if found.returncode > 1:
                invariant_found("store", found.stderr.decode(errors="replace"))
              for match in found.stdout.decode(errors="replace").splitlines():
                path, _, line = match.partition("\0")
                secret = invariant_secret_lines.get(line, "a secret")
                invariant_found("store", f"{path} holds {secret}")
          '')

          (lib.optionalString cfg.leastPrivilege.enable ''
            # NOTE: sops encrypts the values and leaves the keys readable,
            # and every key of the file is a line of its own at the top
            def check_least_privilege(machine, name, file, keys, others):
              content = machine.succeed(f"cat '{file}'")
              if content.lstrip().startswith("{"):
                held = set(invariant_json.loads(content))
              else:
                held = set(invariant_re.findall(r"^([^\s#:][^:]*):", content, invariant_re.M))
              for key in sorted(held - set(keys) - {"sops"}):
                if key in others:
                  invariant_found(name, f"the sops file holds {key}, a secret of another machine")
                  continue
                text = f"the sops file holds {key}, which the machine does not use"
                ${if cfg.leastPrivilege.strict then "invariant_found" else "invariant_warned"}(name, text)

            ${perMachine (
              name: machine:
              let
                keys = sopsKeysOf machine;
                public = builtins.concatMap publicKeysOf (builtins.attrValues machines);
                others = lib.subtractLists (keys ++ public) (
                  builtins.concatMap sopsKeysOf (builtins.attrValues (builtins.removeAttrs machines [ name ]))
                );
              in
              "check_least_privilege(${pythonName name}, '${name}', '${machine.sops.defaultSopsFile}', invariant_json.loads('${builtins.toJSON keys}'), invariant_json.loads('${builtins.toJSON others}'))"
            )}
          '')

          (lib.optionalString cfg.tls.enable ''
            # NOTE: only tcp, and only TLS from the first byte or after the
            # request of postgres; a server that answers a handshake with an
            # alert speaks TLS, it only wants more of the client
            def speaks_tls(machine, target, starttls):
              status, output = machine.execute(
                f"timeout ${builtins.toString cfg.tls.timeout} ${openssl} s_client"
                f" -connect {target} {starttls} </dev/null 2>&1"
              )
              return status == 0 or " alert " in output

            def check_tls(machine, name):
              # NOTE: a server like envoy listens on one port with a socket
              # per worker, so a port is tried once
              tried = set()
              for protocol, address, port, process in network_listeners(machine):
                if protocol != "tcp" or (address, port) in tried:
                  continue
                tried.add((address, port))
                host = "127.0.0.1" if address in ("*", "0.0.0.0", "::") else address
                target = f"[{host}]:{port}" if ":" in host else f"{host}:{port}"
                if speaks_tls(machine, target, "") or speaks_tls(
                  machine, target, "-starttls postgres"
                ):
                  continue
                text = f"tcp {address}:{port} does not speak TLS {process}"
                ${if cfg.tls.strict then "invariant_found" else "invariant_warned"}(name, text)

            ${perMachine (name: _: "check_tls(${pythonName name}, '${name}')")}
          '')

          ''
            if invariant_warnings:
              print("Invariants not held yet:\n" + "\n".join(invariant_warnings))
            assert not invariant_findings, "Invariants broken:\n" + "\n".join(invariant_findings)
          ''
        ];
      };
    };
}
