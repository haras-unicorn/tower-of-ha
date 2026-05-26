# TODO: disks
# TODO: fs instances
# TODO: mount acl

{
  toh.lib.nixosModules.services-ceph =
    {
      lib,
      pkgs,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.cephfs;

      machines = tohLib.serviceMachines "cephfs";
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
              // (lib.optionalAttrs (type == "mon") rec {
                bootstrapServiceName = "ceph-mon-bootstrap-${daemonName}";
                bootstrapService = "${bootstrapServiceName}.service";
                authImportServiceName = "ceph-mon-auth-import-${daemonName}";
                authImportService = "${authImportServiceName}.service";
              })
              // (lib.optionalAttrs (type == "osd") rec {
                bootstrapServiceName = "ceph-osd-bootstrap-${daemonName}";
                bootstrapService = "${bootstrapServiceName}.service";
              })
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

          capacityInMiB = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1024;
            description = "CephFS size in MiB for truncate command";
          };

          fsid = lib.mkOption {
            type = lib.types.str;
            default = "103e0dfc-704d-42b4-a8bb-958d1ceb7d15";
            description = "CephFS ID";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # NOTE: the standard size is 1024,
        # so we just increase it by the ceph disk capacity
        # + a little more space for comfort
        virtualisation.diskSize = 1024 * (cfg.capacityInMiB + 16);

        environment.systemPackages = [
          pkgs.ceph
          pkgs.ceph-client
        ];

        services.ceph = lib.mkMerge (
          [
            {
              enable = true;

              global = {
                fsid = cfg.fsid;
                monInitialMembers = machineNames;
                monHost = ips;
                publicNetwork = network;
                clusterNetwork = network;
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

        systemd.targets.toh-filesystem-initialized =
          let
            services = [ fsEnsureService ] ++ allDaemonServices;
          in
          {
            wantedBy = services;
            bindsTo = services;
            after = services;
          };

        systemd.tmpfiles.rules = [
          # NOTE: needed for the osd loop device service
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
                  path = [ pkgs.ceph ];
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
                  pkgs.ceph
                ];
                script =
                  let
                    addMonitors = builtins.concatStringsSep " " (
                      builtins.map (machine: ''--add "${machine.name}" ${machine.meta.network.ip}'') machines
                    );
                  in
                  ''
                    if [ ! -d "${stateDirectory}/store.db" ]; then
                      monmap="$(mktemp)"
                      trap 'rm -f "$monmap"' EXIT INT TERM
                      rm -rf $monmap
                      monmaptool --create ${addMonitors} --fsid ${cfg.fsid} "$monmap"
                      ceph-mon -i "${name}" \
                        --mkfs \
                        --monmap "$monmap" \
                        --keyring "${config.sops.secrets.${keyring}.path}"
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
                  pkgs.ceph
                ];
                script =
                  builtins.concatStringsSep "\n" (
                    builtins.map
                      (
                        otherKeyringPath:
                        let
                          keyringPath = config.sops.secrets.${keyring}.path;
                        in
                        ''ceph -n mon. -k "${keyringPath}" auth import -i "${otherKeyringPath}"''
                      )
                      (
                        builtins.map ({ value, ... }: value.path) (
                          lib.attrsToList (
                            lib.filterAttrs (
                              name: value: lib.hasPrefix "cephfs" name && lib.hasSuffix "keyring" name && name != keyring
                            ) config.sops.secrets
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
                    pkgs.lvm2
                  ];
                  script = ''
                    mkdir -p "${stateDirectory}"
                    chown ceph:disk -R "${stateDirectory}"
                    chmod 750 -R "${stateDirectory}"
                    img="${stateDirectory}/data.img"
                    if ! losetup -l | grep -q $img; then
                      if [ ! -f $img ]; then
                        truncate -s ${builtins.toString cfg.capacityInMiB}M $img
                      fi
                      dev=$(losetup -f --show $img)
                      if ! ceph-volume raw list | grep -q $dev; then
                        ceph-volume raw prepare --data $dev --osd-id "${name}"
                        ceph-volume raw activate --device $dev --no-systemd
                      fi
                    fi
                  '';
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                };
            })
          ) daemons
        );

        sops.secrets = lib.mkMerge (
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

        toh.cryl.machine = [
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

        toh.cryl.cluster = [
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
