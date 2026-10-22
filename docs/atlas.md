# atlas

Hetzner Cloud VPS, NixOS, workload server behind the reverse-proxy module.
Services live in `hosts/atlas/default.nix`, not documented here (change over time).

## Repo layout

- `hosts/atlas/default.nix` - hostname, profiles, GRUB, reverse-proxied apps.
- `hosts/atlas/disko.nix` - GPT: 1 MiB `EF02` BIOS boot + ext4 root on `/dev/sda`.
- `hosts/atlas/hardware-configuration.nix` - Hetzner Cloud hardware config.
- `flake.nix` - registers `nixosConfigurations.atlas`.

Base image Ubuntu 26.04; NixOS installed on top via `nixos-anywhere`.

## Install / reinstall

From a machine with the right SSH key (e.g. `casper`):

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#atlas \
  --kexec-extra-flags "-c" \
  --ssh-option StrictHostKeyChecking=no \
  --ssh-option UserKnownHostsFile=/dev/null \
  root@<ATLAS_IP>
```

`--kexec-extra-flags "-c"` required: Ubuntu 26.04's kernel rejects
`kexec_file_load`; `-c` forces legacy `kexec_load`. Without it:
`kexec_file_load failed: Address not available`.

## Post-install

1. Make the host a sops recipient (see "Secrets for a new host" in
   `docs/setup.md`): add its SSH age key to `.sops.yaml`, `sops updatekeys`,
   deploy. `tailscale-auth-key` secret joins the tailnet unattended.
2. Tailscale admin console: Machines -> atlas -> disable key expiry
   (else node drops off tailnet after ~180 days).

## Day-to-day commands

```sh
# Build and evaluate
nix build .#nixosConfigurations.atlas.config.system.build.toplevel

# Deploy (MagicDNS name: atlas)
nixos-rebuild switch --flake .#atlas --target-host gabriel@atlas \
  --use-remote-sudo --ask-sudo-password
```

## Useful checks

```sh
systemctl status nginx
systemctl status tailscaled
ss -tlnp | grep -E '80|443'
```

## DNS and app exposure

All apps behind one nginx (`reverse-proxy` module). Two classes:

- **Public** (`public = true`): A record `<subdomain>.gabrielopesantos.com`
  -> public IP, DNS-only (grey cloud); nginx gets its cert via ACME HTTP-01.
- **Private** (default): `<subdomain>.atlas.gabrielopesantos.com`, covered by
  wildcard A record `*.atlas.gabrielopesantos.com` -> tailnet IP
  (`<atlas tailnet IP>`). Name resolves publicly, routes only inside the tailnet;
  vhost binds the tailnet IP exclusively. One wildcard cert via DNS-01 with a
  Cloudflare API token, so private names never hit CT logs.

## SSH

Tailnet-only: `tailscale0` trusted, port 22 closed publicly
(`services.openssh.openFirewall = false`). Break-glass: Hetzner web console.

## Backups

`backup` module (`modules/nixos/backup.nix`, opt-in per host): nightly restic
to private object storage, encrypted, pruned (7 daily/4 weekly/6 monthly),
`restic check` after each run, heartbeat to healthchecks.io. Repository URL
and credentials live in sops (`restic-repository`, `restic-env`), not in the
repo.

Add each new app's state dir to `services.backup.paths`.

Restore drill:

```sh
sudo restic-state snapshots       # wrapper with env/repo/password preset
sudo restic-state restore latest --target /tmp/restore
```

## Updates

`system.autoUpgrade` pulls `github:gabrielopesantos/nixos-configuration`
daily ~04:00, rebuilds; reboots only inside 04:00-06:00. Inputs move only
when `flake.lock` changes on main (weekly `update-flake-lock` PR, merging it by hand). Failed build leaves running system untouched.

## One-time setup checklist (secrets & external services)

Add via `nix develop -c sops secrets/secrets.yaml` (YubiKey inserted):

1. `cloudflare-acme-env` - `CLOUDFLARE_DNS_API_TOKEN=<token>`; Cloudflare
   dashboard, **Zone -> DNS -> Edit** on `gabrielopesantos.com` only.
2. `restic-password` - generate once (`openssl rand -base64 32`), keep a
   copy outside the repo too; losing it loses the backups.
3. `restic-env` - env file with the storage backend's credentials, from a key
   scoped to the backup bucket only (private bucket).
4. `restic-repository` - restic repository URL for that backend.
5. `healthchecks-url` - ping URL from a healthchecks.io check, period 1 day.

External, outside the repo:

1. Cloudflare DNS: wildcard A record `*.atlas.gabrielopesantos.com` ->
   `<atlas tailnet IP>` (grey cloud).
2. After first deploy, verify SSH still works over the tailnet from a new
   terminal before closing the deploying session.

## Reverse proxy security note

Module forwards each subdomain to `address:port` (default
`address = "127.0.0.1"`). App must bind that address, not `0.0.0.0`, or it's
reachable directly on the public IP, bypassing nginx/TLS.

Native NixOS services: firewall only opens 80/443, so it's the safety net.
OCI containers: publish the port to loopback explicitly
(`127.0.0.1:3000:3000`) - container runtimes can inject iptables rules that
bypass the NixOS firewall.

```nix
services.reverseProxy.apps.myapp = {
  subdomain = "myapp";
  port = 3000;
};

virtualisation.oci-containers.containers.myapp = {
  image = "myapp:latest";
  ports = [ "127.0.0.1:3000:3000" ];
};
```
