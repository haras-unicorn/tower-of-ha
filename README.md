# Tower Of HA

Tower Of HA is a highly opinionated, free and highly available service stack.

The opinions for Tower Of HA are entirely my own and are subject to change but
the core principles are:

- battle-tested software
- FOSS software
- downtime minimization
- software accommodates for cheap hardware
- stability and resilience over performance

## Services

- VPN: [WireGuard] + [Headscale] + [Tailscale] + [ddns-updater]
- SSH: [OpenSSH]
- FS: [CephFS] + [Samba] + [CTDB] + [FUSE]
- DB: [PostgreSQL] + [Patroni] + [etcd] + [HAProxy]
- Proxy: [HAProxy]
- DNS: [CoreDNS]
- S3: [Garage]
- Cache: [Valkey]
- Secrets: [OpenBao]
- Passwords: [Vaultwarden]
- Email: [Postfix] + [Dovecot]
- Git: [Forgejo]
- Observability: [Prometheus] + [AlertManager]

## CLI

```bash
toh status    # Check all services are running
toh backup    # Backup everything locally
toh deploy    # Deploy all machines
toh ssh       # SSH shell
toh sql       # PostgreSQL shell
toh mount     # Mount CephFS as transient systemd service
```

## External requirements

- DNS name ([Cloudflare DNS], [GoDaddy DNS], etc.)
- S3 bucket for cloud backups ([Cloudflare R2], [AWS S3], etc.)
- Email proxy ([addy.io], [SimpleLogin], etc.)

## Hardware

Tower of HA makes no assumptions about the hardware you use but as NixOS is used
for IaC your hardware needs to support it. This includes most VPS services,
NUC's, servers, etc.

## Connecting to the stack

Tower of HA assumes you will want to connect to it with various devices like
PC's, mobile phones, etc. Steps to connect include:

- Install the tower's SSL CA certificate on your device
- Configure your device to use the tower's DNS servers
- Add the tower's network via TailScale client
- Map Samba shares using your credentials
- Add vaultwarden to your Bitwarden client
- Configure email client with your tower's mail server

[WireGuard]: https://www.wireguard.com/
[Headscale]: https://headscale.net/
[ddns-updater]: https://github.com/qdm12/ddns-updater
[Tailscale]: https://tailscale.com/
[OpenSSH]: https://www.openssh.com/
[CephFS]: https://docs.ceph.com/
[Samba]: https://www.samba.org/
[CTDB]: https://ctdb.samba.org/
[FUSE]: https://github.com/libfuse/libfuse
[PostgreSQL]: https://www.postgresql.org/
[Patroni]: https://patroni.readthedocs.io/
[etcd]: https://etcd.io/
[HAProxy]: https://www.haproxy.org/
[CoreDNS]: https://coredns.io/
[Garage]: https://garagehq.deuxfleurs.fr/
[Valkey]: https://valkey.io/
[OpenBao]: https://www.openbao.org/
[Vaultwarden]: https://github.com/dani-garcia/vaultwarden
[Postfix]: http://www.postfix.org/
[Dovecot]: https://www.dovecot.org/
[Forgejo]: https://forgejo.org/
[Prometheus]: https://prometheus.io/
[AlertManager]: https://prometheus.io/docs/alerting/latest/alertmanager/
[Cloudflare DNS]: https://www.cloudflare.com/dns/
[GoDaddy DNS]: https://www.google.com/search?q=godaddy
[Cloudflare R2]: https://www.cloudflare.com/products/r2/
[AWS S3]: https://aws.amazon.com/s3/
[addy.io]: https://addy.io/
[SimpleLogin]: https://simplelogin.io/
