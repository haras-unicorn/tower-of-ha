# TODO: disks
# TODO: fs instances
# TODO: mount acl

{ selfLib, ... }:

{
  self.nixosModules.services-ceph.flake = true;
  self.nixosModules.services-ceph.value =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.toh.services.cephfs;

      cephPackage = pkgs.ceph;

      machines = selfLib.cluster.serviceMachines config "cephfs";
      ips = builtins.concatStringsSep "," (builtins.map (machine: machine.meta.network.ip) machines);
      machineNames = builtins.concatStringsSep "," (builtins.map (machine: machine.name) machines);

      network =
        config.toh.meta.network.subnet.ip + "/" + (builtins.toString config.toh.meta.network.subnet.bits);

      daemons =
        builtins.concatMap
          (
            { name, value, ... }:
            builtins.map (
              daemonName:
              let
                type = name;
                serviceName = "ceph-${type}-${daemonName}";
              in
              {
                inherit type serviceName;
                name = daemonName;
                service = "${serviceName}.service";
                key = "cephfs-${type}-key";
                keyring = "cephfs-${type}-keyring";
                # NOTE: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/network-filesystems/ceph.nix
                # id gladly user the service config themselves
                # but that would cause infinite recursion here
                # because we are using this in a systemd.service mkMerge
                stateDirectory =
                  "/var/lib/ceph/"
                  + (if type == "rgw" then "radosgw" else type)
                  + "/"
                  + config.services.ceph.global.clusterName
                  + "-"
                  + daemonName;
                user = "ceph";
                group = if type == "osd" then "disk" else "ceph";
              }
              // (lib.optionalAttrs (type == "mon") (
                let
                  bootstrapServiceName = "ceph-mon-bootstrap-${daemonName}";
                  authImportServiceName = "ceph-mon-auth-import-${daemonName}";
                in
                {
                  inherit bootstrapServiceName authImportServiceName;
                  bootstrapService = "${bootstrapServiceName}.service";
                  authImportService = "${authImportServiceName}.service";
                }
              ))
              // (lib.optionalAttrs (type == "osd") (
                let
                  bootstrapServiceName = "ceph-osd-bootstrap-${daemonName}";
                in
                {
                  inherit bootstrapServiceName;
                  bootstrapService = "${bootstrapServiceName}.service";
                }
              ))
            ) value.daemons
          )
          (
            lib.attrsToList (
              lib.filterAttrs (_: value: builtins.isAttrs value && value ? daemons) config.services.ceph
            )
          );

      afterAllServices = [
        "toh-network-online.target"
        "toh-time-synchronized.target"
      ];

      monAuthImportServices = builtins.map ({ authImportService, ... }: authImportService) (
        builtins.filter ({ type, ... }: type == "mon") daemons
      );

      monBootstrapServices = builtins.map ({ bootstrapService, ... }: bootstrapService) (
        builtins.filter ({ type, ... }: type == "mon") daemons
      );

      osdBootstrapServices = builtins.map ({ bootstrapService, ... }: bootstrapService) (
        builtins.filter ({ type, ... }: type == "osd") daemons
      );

      allDaemonServices =
        builtins.map ({ service, ... }: service) daemons
        ++ monBootstrapServices
        ++ monAuthImportServices
        ++ osdBootstrapServices;

      fsEnsureServiceName = "ceph-fs-ensure-volume";
      fsEnsureService = "${fsEnsureServiceName}.service";
    in
    {
      options.toh.services = {
        cephfs = {
          enable = lib.mkEnableOption "CephFS";

          capacityInMB = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1024;
            description = "CephFS size in MB for truncate command";
          };

          fsid = lib.mkOption {
            type = lib.types.str;
            default = "103e0dfc-704d-42b4-a8bb-958d1ceb7d15";
            description = "CephFS ID";
          };

          keyType = lib.mkOption {
            type = lib.types.enum [
              "aes256k"
              "aes"
            ];
            default = "aes256k";
            description = ''
              The key type clients may use. Kernels before 7.0 can only mount
              with the older and less secure aes keys, so `aes` also allows
              those. Only takes effect when the monitors are first created,
              and the keys cryl generates do not follow it yet.
            '';
          };

          silentClientEviction = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60;
            description = ''
              Seconds after which the metadata servers evict a client that
              stopped renewing its session, like the mount of a machine that
              went away, so the files it held open are free again
              (`session_autoclose` of the filesystem). Ceph waits 300 by
              default, longer than a failover may take.
            '';
          };

          monitorDownGrace = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60;
            description = ''
              Seconds the monitors wait, while one of them is down or they
              just elected a leader, before they replace a metadata server
              that went silent (`mds_beacon_mon_down_grace`). Killing a
              machine takes out its monitor too, so a failover of the active
              metadata server waits this long.
            '';
          };

          reconnectTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 45;
            description = ''
              Seconds a metadata server that takes over waits for the clients
              it knew to come back (`mds_reconnect_timeout`). The mount of a
              machine that went away never does, so a failover waits this
              long too.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cephPackage
          pkgs.ceph-client
        ];

        services.ceph = lib.mkMerge (
          [
            {
              enable = true;

              mgr.package = cephPackage;
              mon.package = cephPackage;
              osd.package = cephPackage;
              mds.package = cephPackage;
              rgw.package = cephPackage;

              global = {
                mgrModulePath = "${cephPackage.lib}/lib/ceph/mgr";
                fsid = cfg.fsid;
                monInitialMembers = machineNames;
                monHost = ips;
                publicNetwork = network;
                clusterNetwork = network;
              };

              extraConfig = {
                "mds beacon mon down grace" = builtins.toString cfg.monitorDownGrace;
                "mds reconnect timeout" = builtins.toString cfg.reconnectTimeout;
              };
            }
          ]
          ++
            builtins.map
              (name: {
                ${name} = {
                  enable = true;
                  daemons =
                    if name == "osd" then
                      [ (builtins.toString config.toh.meta.machine.index) ]
                    else
                      [ config.toh.meta.machine.name ];
                };
              })
              [
                "mon"
                "mgr"
                "osd"
                "mds"
              ]
        );

        systemd.targets.toh-filesystem-online =
          let
            services = [ fsEnsureService ] ++ allDaemonServices;
          in
          {
            wantedBy = services;
            bindsTo = services;
            after = services;
          };

        systemd.tmpfiles.rules = [
          "d /var/log/ceph 0750 ceph ceph -"
          "d /var/lib/ceph/bootstrap-osd 0750 ceph ceph -"
        ];

        networking.firewall.allowedTCPPorts = [
          # NOTE: monitor ports
          3300
          6789
          # NOTE: manager dashboard HTTP port
          8080
        ];

        networking.firewall.allowedTCPPortRanges = [
          # NOTE: manager, object storage, metadata take
          # first available from this range
          {
            from = 6800;
            to = 7568;
          }
        ];

        systemd.services = lib.mkMerge (
          [
            (
              let
                afterServices = afterAllServices ++ allDaemonServices;
              in
              {
                ${fsEnsureServiceName} = {
                  description = "Ensure default CephFS volume exists";
                  wantedBy = afterServices;
                  after = afterServices;
                  requires = afterServices;
                  path = [ cephPackage ];
                  script = ''
                    while ! ceph fs volume ls >/dev/null 2>&1; do
                      echo "Waiting for volume commands to be ready..."
                      sleep 1
                    done

                    if ! ceph fs get ceph >/dev/null 2>&1; then
                      ceph fs volume create ceph
                      ceph osd pool application enable cephfs.ceph.meta cephfs
                      ceph osd pool application enable cephfs.ceph.data cephfs
                    fi

                    ceph fs set ceph session_autoclose ${builtins.toString cfg.silentClientEviction}
                  '';
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    User = "ceph";
                    Group = "ceph";
                  };
                };
              }
            )
          ]
          ++ builtins.map (
            {
              serviceName,
              type,
              name,
              stateDirectory,
              keyring,
              service,
              bootstrapService ? null,
              bootstrapServiceName ? null,
              authImportService ? null,
              authImportServiceName ? null,
              ...
            }:
            let
              afterServices =
                lib.optional (type == "mon" || type == "osd") bootstrapService
                ++ lib.optionals (type != "mon") monAuthImportServices;
            in
            {
              ${serviceName} = {
                wantedBy = afterAllServices ++ afterServices;
                after = afterAllServices ++ afterServices;
                requires = afterAllServices ++ afterServices;
              };
            }
            // (lib.optionalAttrs (type == "mon") {
              ${bootstrapServiceName} = {
                wantedBy = afterAllServices;
                after = afterAllServices;
                requires = afterAllServices;
                path = [
                  cephPackage
                ];
                script =
                  let
                    addMonitors = builtins.concatStringsSep " " (
                      builtins.map (
                        machine:
                        let
                          ip = machine.meta.network.ip;
                        in
                        ''--addv "${machine.name}" "[v2:${ip}:3300,v1:${ip}:6789]"''
                      ) machines
                    );

                    authSettings = lib.optionalString (cfg.keyType == "aes") "--auth-allowed-ciphers=aes,aes256k";
                  in
                  ''
                    if [ ! -d "${stateDirectory}/store.db" ]; then
                      monmap="$(mktemp)"
                      trap 'rm -f "$monmap"' EXIT INT TERM
                      rm -rf $monmap
                      monmaptool --create ${authSettings} ${addMonitors} --fsid ${cfg.fsid} "$monmap"
                      ceph-mon -i "${name}" \
                        --mkfs \
                        --monmap "$monmap" \
                        --keyring "${config.toh.meta.sops.secrets.${keyring}.path}"
                    fi
                  '';
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  User = "ceph";
                  Group = "ceph";
                };
              };

              ${authImportServiceName} = {
                wantedBy = afterAllServices ++ [ service ];
                after = afterAllServices ++ [ service ];
                requires = afterAllServices ++ [ service ];
                path = [
                  cephPackage
                ];
                script =
                  builtins.concatStringsSep "\n" (
                    builtins.map
                      (
                        otherKeyringPath:
                        let
                          keyringPath = config.toh.meta.sops.secrets.${keyring}.path;
                        in
                        ''ceph -n mon. -k "${keyringPath}" auth import -i "${otherKeyringPath}"''
                      )
                      (
                        builtins.map ({ value, ... }: value.path) (
                          lib.attrsToList (
                            lib.filterAttrs (
                              name: value: lib.hasPrefix "cephfs" name && lib.hasSuffix "keyring" name && name != keyring
                            ) config.toh.meta.sops.secrets
                          )
                        )
                      )
                  )
                  + "\n"
                  + "ceph config set mon auth_allow_insecure_global_id_reclaim false"
                  + "\n"
                  + "ceph mon enable-msgr2"
                  + "\n"
                  + "ceph -s";
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  User = "ceph";
                  Group = "ceph";
                };
              };
            })
            // (lib.optionalAttrs (type == "osd") {
              ${bootstrapServiceName} =
                let
                  afterServices = builtins.map ({ service, ... }: service) (
                    builtins.filter ({ type, ... }: type != "osd") daemons
                  );
                in
                {
                  wantedBy = afterAllServices ++ afterServices ++ monAuthImportServices;
                  after = afterAllServices ++ afterServices ++ monAuthImportServices;
                  requires = afterAllServices ++ afterServices ++ monAuthImportServices;
                  path = [
                    config.services.ceph.osd.package
                    pkgs.util-linux
                  ];
                  # NOTE: ceph-volume only prepares block devices, and a
                  # loop device for a file needs /dev/loop-control, which
                  # containers lack; bluestore can keep its data in a plain
                  # file, so this does by hand what ceph-volume would do
                  script =
                    let
                      bootstrapAuth = "-n client.bootstrap-osd -k /var/lib/ceph/bootstrap-osd/ceph.keyring";
                      capacityInBytes = builtins.toString (cfg.capacityInMB * 1000 * 1000);
                    in
                    ''
                      dir="${stateDirectory}"
                      if [ -f "$dir/ready" ]; then
                        exit 0
                      fi

                      mkdir -p "$dir"
                      if [ ! -f "$dir/osd-uuid" ]; then
                        uuidgen > "$dir/osd-uuid"
                      fi
                      uuid="$(cat "$dir/osd-uuid")"
                      if [ ! -f "$dir/keyring" ]; then
                        ceph-authtool "$dir/keyring" --create-keyring \
                          --name "osd.${name}" --add-key "$(ceph-authtool --gen-print-key)"
                      fi
                      secret="$(ceph-authtool "$dir/keyring" --name "osd.${name}" --print-key)"

                      echo "{\"cephx_secret\": \"$secret\"}" \
                        | ceph ${bootstrapAuth} -i - osd new "$uuid" "${name}"
                      ceph ${bootstrapAuth} mon getmap -o "$dir/activate.monmap"
                      echo "$secret" | ceph-osd -i "${name}" --mkfs \
                        --osd-uuid "$uuid" \
                        --osd-data "$dir" \
                        --osd-objectstore bluestore \
                        --monmap "$dir/activate.monmap" \
                        --keyfile - \
                        --bluestore_block_create=true \
                        --bluestore_block_size=${capacityInBytes}

                      chown ceph:disk -R "$dir"
                      chmod 750 -R "$dir"
                    '';
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                };
            })
          ) daemons
        );

        toh.meta.sops.secrets = lib.mkMerge (
          builtins.map (
            {
              stateDirectory,
              keyring,
              user,
              group,
              type,
              ...
            }:
            {
              ${keyring} = {
                path =
                  if type == "mon" then
                    "/etc/ceph/ceph.mon..keyring"
                  else if type == "osd" then
                    "/var/lib/ceph/bootstrap-osd/ceph.keyring"
                  else
                    "${stateDirectory}/keyring";
                owner = user;
                group = group;
                mode = "0400";
              };
            }
          ) daemons
        );

        toh.meta.cryl.machine = [
          {
            cephfs = {
              generations = builtins.concatMap (
                {
                  key,
                  keyring,
                  type,
                  name,
                  ...
                }:
                [
                  {
                    generator = "mustache";
                    arguments = {
                      name = keyring;
                      renew = true;
                      listing = {
                        type = "map";
                        value = {
                          CEPH_DAEMON_KEY = "cluster/${key}";
                        };
                      };
                      template =
                        let
                          entity =
                            if type == "mon" then
                              "mon."
                            else if type == "osd" then
                              "client.bootstrap-osd"
                            else
                              "${type}.${name}";
                          caps =
                            if type == "mon" then
                              ''
                                caps mon = "allow *"
                              ''
                            else if type == "mgr" then
                              ''
                                caps osd = "allow *"
                                caps mds = "allow *"
                                caps mon = "allow profile mgr"
                              ''
                            else if type == "osd" then
                              ''
                                caps mon = "profile bootstrap-osd"
                              ''
                            else if type == "mds" then
                              ''
                                caps mds = "allow *"
                                caps osd = "allow *"
                                caps mon = "allow profile mds"
                              ''
                            else
                              "";
                        in
                        ''
                          [${entity}]
                          key = {{{CEPH_DAEMON_KEY}}}
                          ${caps}
                        '';
                    };
                  }
                ]
              ) daemons;
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            cephfs = {
              generations = builtins.concatMap (
                { type, key, ... }:
                [
                  {
                    generator = "ceph-key";
                    arguments.name = key;
                  }
                ]
              ) daemons;
            };
          }
        ];

        toh.services.cephfs.installAdminKeyring = true;
      };
    };
}
