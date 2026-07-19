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

## DNS

The configured subdomain is an A record pointing at `<ATLAS_IP>`. It should be kept
DNS-only (grey cloud) in Cloudflare so nginx can obtain and serve its own Let's Encrypt
certificate via ACME HTTP-01.

## Homepage (tailnet-only)

`homepage-dashboard` is deliberately *not* behind the public reverse proxy.
It binds loopback only (`HOSTNAME=127.0.0.1`, port 8082) and is published to
the tailnet by the `tailscale-serve-homepage` unit:

- Address: **`https://atlas.tailcadc07.ts.net`** — from any tailnet device.
- `tailscale serve` terminates TLS inside tailscaled with an automatic
  Let's Encrypt certificate for the ts.net name, then proxies to
  `127.0.0.1:8082`. Requires MagicDNS + HTTPS certificates enabled on the
  tailnet.
- Bare `https://atlas` cannot work: public CAs don't issue certificates for a
  bare hostname, so the TLS handshake has nothing valid to present. Use the
  FQDN (or add a plain-HTTP `--http=80` serve if `http://atlas` is ever
  wanted; tailnet traffic is WireGuard-encrypted either way).
- Testing from atlas itself always hits nginx instead — serve interception
  only applies to connections from *other* tailnet nodes. Verify from casper.

The unit is ordered after `tailscaled-autoconnect.service`; serve commands
fail while the node is logged out, and autoconnect is what completes the
auth-key login on first boot.

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
