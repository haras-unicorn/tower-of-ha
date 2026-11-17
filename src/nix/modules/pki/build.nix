{
  toh.lib.nixosModules.pki-build-on-activation =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.security.pki;

      cacertPackage = pkgs.cacert.override {
        blacklist = cfg.caCertificateBlacklist;
        extraCertificateFiles = cfg.certificateFiles;
        extraCertificateStrings = cfg.certificates;
      };

      buildCaBundleAndP11KitTrust = pkgs.writeShellApplication {
        name = "build-ca-bundle-and-p11-kit-trust";
        runtimeInputs = [
          pkgs.buildcatrust
        ];
        text =
          let
            caBundlePath = config.security.pki.caBundlePackage;
            caBundleDir = builtins.dirOf caBundlePath;

            caP11KitTrustPath = config.security.pki.caP11KitTrustPackage;
            caP11KitTrustDir = builtins.dirOf caP11KitTrustPath;

            allCertFiles = cfg.certificateFiles ++ cfg.certificatePaths;
            extraBundleFile = builtins.toFile "extra-certs.crt" (lib.concatStringsSep "\n" cfg.certificates);
            blocklistFile = builtins.toFile "blocklist.txt" (
              lib.concatStringsSep "\n" cfg.caCertificateBlacklist
            );
            bundleOutput = if cfg.useCompatibleBundle then "ca-no-trust-rules-bundle.crt" else "ca-bundle.crt";
          in
          ''
            echo "Building CA bundle..." >&2
            tmpdir=$(mktemp -d)
            trap 'rm -rf "$tmpdir"' EXIT

            extraBundle="$tmpdir/extra.crt"
            cat ${extraBundleFile} > "$extraBundle"
            ${lib.concatStringsSep "\n" (map (f: "cat ${f} >> \"$extraBundle\"") allCertFiles)}

            mkdir -p "$tmpdir/unbundled"
            mkdir -p "$tmpdir/hashed"
            buildcatrust \
              --certdata_input ${pkgs.cacert.src} \
              --ca_bundle_input "$extraBundle" \
              --blocklist ${blocklistFile} \
              --ca_bundle_output "$tmpdir/ca-bundle.crt" \
              --ca_standard_bundle_output "$tmpdir/ca-no-trust-rules-bundle.crt" \
              --ca_unpacked_output "$tmpdir/unbundled" \
              --ca_hashed_unpacked_output "$tmpdir/hashed" \
              --p11kit_output "$tmpdir/ca-bundle.trust.p11-kit"
            echo "CA bundle successfully built..." >&2

            mkdir -p "${caBundleDir}"
            chmod 755 "${caBundleDir}"

            cp "$tmpdir/${bundleOutput}" "${caBundlePath}.new"
            mv "${caBundlePath}.new" "${caBundlePath}"
            chmod 644 "${caBundlePath}"

            mkdir -p "${caP11KitTrustDir}"
            chmod 755 "${caP11KitTrustDir}"

            cp "$tmpdir/ca-bundle.trust.p11-kit" "${caP11KitTrustPath}.new"
            mv "${caP11KitTrustPath}.new" "${caP11KitTrustPath}"
            chmod 644 "${caP11KitTrustPath}"

            echo "CA bundle successfully installed..." >&2
          '';
      };
    in
    {
      options = {
        security.pki = {
          caP11KitTrustPackage = lib.mkOption {
            type = lib.types.path;
            internal = true;
          };

          caP11KitTrust = lib.mkOption {
            type = lib.types.path;
            readOnly = true;
            description = ''
              (Read-only) the path to the final p11-kit trust of certificate authorities as a single file.
            '';
          };

          certificatePaths = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            example = lib.literalExpression ''[ "/persist/certs/myca.crt" ]'';
            description = ''
              Extra CA cert files added during activation (merged with certificateFiles).
              Use for runtime-managed certs.
            '';
          };

          buildOnActivation = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Build CA bundle during activation using merged certs.
              Overrides security.pki.installCACerts.
            '';
          };

          buildWithService = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Build CA bundle with systemd service using merged certs.
              Overrides security.pki.installCACerts.
            '';
          };

          buildPackage = lib.mkOption {
            type = lib.types.package;
            default = pkgs.buildCaBundleAndP11KitTrust;
            description = ''
              Package with which to build CA bundle and p11-kit trust on activation or with service.
            '';
          };
        };
      };

      config = lib.mkMerge [
        {
          security.pki.caP11KitTrustPackage = "${cacertPackage.p11kit}/etc/ssl/trust-source/ca-bundle.trust.p11-kit";
          security.pki.caP11KitTrust = cfg.caP11KitTrustPackage;
          nixpkgs.overlays = [
            (final: prev: {
              inherit buildCaBundleAndP11KitTrust;
            })
          ];
        }
        (lib.mkIf cfg.installCACerts {
          environment.etc."ssl/trust-source".enable = false;
          environment.etc."ssl/trust-source/ca-bundle.trust.p11-kit".source = cfg.caP11KitTrust;
        })
        (lib.mkIf (cfg.buildOnActivation || cfg.buildWithService) {
          security.pki.caBundlePackage = lib.mkOverride (
            lib.modules.defaultOverridePriority - 1
          ) "/etc/ssl/certs/ca-certificates.crt";
          security.pki.caP11KitTrustPackage = lib.mkOverride (
            lib.modules.defaultOverridePriority - 1
          ) "/etc/ssl/trust-source/ca-bundle.trust.p11-kit";

          security.pki.installCACerts = false;
          environment.etc."ssl/certs/ca-bundle.crt".source = cfg.caBundle;
          environment.etc."pki/tls/certs/ca-bundle.crt".source = cfg.caBundle;
        })
        (lib.mkIf cfg.buildOnActivation {
          system.activationScripts.build-ca-bundle-and-p11-kit-trust = {
            text = lib.getExe cfg.buildPackage;
          };
        })
        (lib.mkIf cfg.buildWithService {
          systemd.services.build-ca-bundle-and-p11-kit-trust = {
            wantedBy = [ "sysinit.target" ];
            after = [ "local-fs.target" ];
            requiredBy = [ "sysinit-reactivation.target" ];
            before = [ "sysinit-reactivation.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe cfg.buildPackage;
              RemainAfterExit = true;
            };
            unitConfig.DefaultDependencies = "no";
            unitConfig.RequiresMountsFor = cfg.certificatePaths;
          };
        })
      ];
    };
}
