# atlas

Hetzner Cloud VPS running NixOS, configured as a workload server behind the
reverse-proxy module. The actual services on the host are defined in
`hosts/atlas/default.nix` and are intentionally not documented here because they
change over time.

## Hardware / platform

- **Host:** Hetzner Cloud VPS, x86_64.
- **Public IP:** `<ATLAS_IP>` (use the value from the `infrastructure` Terraform output, `server_ipv4`).
- **Private IP:** assigned by the Hetzner private network (see the `infrastructure` Terraform output).
- **Boot:** Hetzner Cloud VMs use legacy BIOS (SeaBIOS), not UEFI. This means
  GRUB with a GPT BIOS boot partition (`EF02`), not `systemd-boot` + ESP.

## Repo layout

The host is declared in this flake:

- `hosts/atlas/default.nix` — hostname, profiles, GRUB, and reverse-proxied apps.
- `hosts/atlas/disko.nix` — GPT layout: 1 MiB `EF02` BIOS boot partition + ext4 root on `/dev/sda`.
- `hosts/atlas/hardware-configuration.nix` — minimal Hetzner Cloud hardware config.
- `flake.nix` — registers `nixosConfigurations.atlas`.

The VM and firewall are provisioned by the separate `infrastructure` Terraform repo
(`hetzner-vps` module). The base image is Ubuntu 26.04; NixOS is installed on top with
`nixos-anywhere`.

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

The `--kexec-extra-flags "-c"` is required because Ubuntu 26.04's kernel rejects the
`kexec_file_load` syscall that `nixos-anywhere` uses by default. The `-c` flag forces
the legacy `kexec_load` syscall instead. Without it the install fails with
`kexec_file_load failed: Address not available`.

## Post-install

1. Make the host a sops recipient (see "Secrets for a new host" in
   `docs/setup.md`): add its SSH age key to `.sops.yaml`, `sops updatekeys`,
   deploy. With the `tailscale-auth-key` secret it joins the tailnet
   unattended — no manual `tailscale up`.
2. In the Tailscale admin console: Machines → atlas → Disable key expiry
   (otherwise the node drops off the tailnet after ~180 days).

## Day-to-day commands

```sh
# Build and evaluate the configuration
nix build .#nixosConfigurations.atlas.config.system.build.toplevel

# Deploy once the host is on the tailnet (MagicDNS name: atlas)
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

All apps sit behind one nginx (the `reverse-proxy` module). Two classes:

- **Public apps** (`public = true`): explicit A record
  `<subdomain>.gabrielopesantos.com` → public IP, kept DNS-only (grey cloud)
  in Cloudflare so nginx can obtain its own cert via ACME HTTP-01.
- **Private apps** (the default): served at
  `<subdomain>.atlas.gabrielopesantos.com`, covered by a single wildcard A
  record `*.atlas.gabrielopesantos.com` → the tailnet IP (`100.83.163.93`).
  The name resolves publicly but only routes inside the tailnet, and the
  vhost additionally binds the tailnet IP exclusively. One wildcard cert
  `*.atlas.gabrielopesantos.com` is obtained via DNS-01 with a Cloudflare API
  token, so private app names never appear in certificate-transparency logs.

`homepage-dashboard` is a private app at
`https://home.atlas.gabrielopesantos.com` (loopback-bound on port 8082,
proxied by nginx). The old `tailscale serve` publication is gone.

## SSH

Tailnet-only: `tailscale0` is a trusted firewall interface and port 22 is not
opened publicly (`services.openssh.openFirewall = false`). If the tailnet is
ever unreachable, use the Hetzner web console as break-glass access.

## Backups

The reusable `backup` module (`modules/nixos/backup.nix`, opt-in per host)
runs a nightly restic backup of app state directories to Backblaze B2
(bucket `atlas-backups`), encrypted, pruned (7 daily / 4 weekly / 6 monthly),
with a full `restic check` after each run. Success/failure is reported to a
healthchecks.io check — silence alerts.

Add each new app's state directory to `services.backup.paths` when the app
lands on the host.

Restore drill:

```sh
sudo restic-state snapshots       # wrapper with env/repo/password preset
sudo restic-state restore latest --target /tmp/restore
```

## Updates

`system.autoUpgrade` pulls `github:gabrielopesantos/nixos-configuration`
daily at ~04:00 and rebuilds; reboots (kernel/systemd bumps) happen only
inside the 04:00–06:00 window. Inputs only move when `flake.lock` changes on
main: the `update-flake-lock` GitHub Action opens a weekly PR, and merging it
is the human gate. A failed build leaves the running system untouched.

## One-time setup checklist (secrets & external services)

The config references sops keys that must exist before deploying. Add them
with `nix develop -c sops secrets/secrets.yaml` (YubiKey inserted):

1. `cloudflare-acme-env` — literal line
   `CLOUDFLARE_DNS_API_TOKEN=<token>`; create the token in the Cloudflare
   dashboard with **Zone → DNS → Edit** on `gabrielopesantos.com` only.
2. `restic-password` — generate once (`openssl rand -base64 32`) and keep it
   safe outside the repo too; losing it means losing the backups.
3. `restic-env` — two lines: `B2_ACCOUNT_ID=<keyID>` and
   `B2_ACCOUNT_KEY=<applicationKey>`, from a Backblaze application key
   scoped to the `atlas-backups` bucket (create the bucket first, private).
4. `healthchecks-url` — ping URL from a new check on healthchecks.io
   (e.g. `https://hc-ping.com/<uuid>`), expected period 1 day.

External, outside the repo:

5. Cloudflare DNS: wildcard A record `*.atlas.gabrielopesantos.com` →
   `100.83.163.93` (grey cloud); keep `kuma.gabrielopesantos.com` → public
   IP (grey cloud).
6. UptimeRobot (or similar): HTTPS monitor on
   `https://kuma.gabrielopesantos.com` — external "is atlas alive" alert.
7. After the first deploy, verify SSH still works over the tailnet from a
   *new* terminal before closing the session that deployed.

## Reverse proxy security note

The reverse proxy module forwards each subdomain to `address:port` (default `address =
"127.0.0.1"`). The app process must bind to that address, not the wildcard `0.0.0.0`, or
it can be reached directly on the public IP and bypass nginx/TLS.

For native NixOS services the module only opens ports 80/443 in the firewall, so the
firewall is the safety net if a service happens to bind wide. For OCI containers
(Docker/Podman), publish the container port to loopback explicitly, e.g.
`127.0.0.1:3000:3000`, because container runtimes can inject iptables rules that bypass
the NixOS firewall.

Example with an OCI container:

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
