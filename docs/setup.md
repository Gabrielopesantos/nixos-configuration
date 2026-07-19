# Setup and usage

## First install on casper (fresh ISO)

To switch it to NixOS:

1. Write the NixOS ISO to USB, boot it.
2. **Confirm the disk** and update `device` in `hosts/casper/disko.nix`
   (prefer a stable `/dev/disk/by-id/...` path):
   ```sh
   lsblk; ls -l /dev/disk/by-id
   ```
3. Partition + format + mount via disko (DESTRUCTIVE - wipes the disk):
   ```sh
   sudo nix --experimental-features "nix-command flakes" run \
     github:nix-community/disko/latest -- \
     --mode destroy,format,mount --flake .#casper /mnt
   ```
4. Generate the real hardware config (disko owns the filesystems):
   ```sh
   sudo nixos-generate-config --no-filesystems --root /mnt
   # copy /mnt/etc/nixos/hardware-configuration.nix over
   # hosts/casper/hardware-configuration.nix in this repo
   ```
5. Install from the flake:
   ```sh
   sudo nixos-install --flake <path-to-repo>#casper
   ```
6. Reboot. Log in as `gabriel` (password = the `gabriel-password` hash in
   sops). Then commit the real `hardware-configuration.nix`.

## Secrets (sops-nix)

Bootstrapped and live. One shared encrypted store, `secrets/secrets.yaml`,
committed to the repo; recipients are declared in `.sops.yaml`.

### How it works

sops uses **envelope encryption**: each file carries one random AES-256-GCM
*data key* that encrypts every value in it. That data key is then wrapped once
per recipient, so any single recipient can unwrap it and read the file. A MAC
over the content detects tampering. Current recipients:

- **Your YubiKey GPG key** (`pgp` in `.sops.yaml`) — the *editor* identity.
  Needed (plugged in, `gpg-agent` running) only when you create or edit
  secrets on your workstation. Never needed by any host.
- **Each host's SSH host key as age** (`age` in `.sops.yaml`) — the *machine*
  identities. At activation, sops-nix uses `/etc/ssh/ssh_host_ed25519_key` to
  decrypt secrets to `/run/secrets/<name>` (tmpfs, root-only). This is what
  makes servers fully unattended: no YubiKey, no passphrase.

Losing the YubiKey does not lock anything: hosts keep decrypting, and any host
key can recover editor access (`ssh-to-age -private-key`).

### Editing secrets

`sops` lives in the dev shell:

```sh
nix develop -c sops secrets/secrets.yaml
```

Decrypts into `$EDITOR` (YubiKey PIN prompt), re-encrypts on save. Key names
are visible in the committed file; only values are encrypted.

Secrets currently in the store:

- `tailscale-auth-key` — reusable tailnet auth key; makes enrollment of new
  machines unattended (`profiles/tailscale.nix` picks it up automatically).
  Auth keys expire (max 90 days): already-enrolled hosts are unaffected, but
  enrolling a *new* machine after expiry needs a fresh key pasted here.
- `gabriel-password` — yescrypt hash (`mkpasswd -m yescrypt`) consumed by
  `hashedPasswordFile` in `profiles/common.nix`. `users.mutableUsers = false`,
  so this hash is authoritative on every activation and `passwd` on a host has
  no lasting effect.

### Tailscale key expiry

Two different expiries to keep straight:

- **Auth key** (in sops): only gates *new* enrollments; rotate via the admin
  console + `sops` when needed.
- **Node keys**: each enrolled machine's key expires after ~180 days by
  default, which would drop it off the tailnet. Disable per machine in the
  admin console (Machines → … → Disable key expiry) — do this for every
  long-lived host. Not settable from Nix.

## Day-to-day

```sh
sudo nixos-rebuild switch --flake .#casper   # apply changes
nix flake update                             # bump all inputs
nix flake check                              # evaluate everything
nix fmt                                      # format (nixfmt-rfc-style)
```

## Adding a machine

### Laptop

1. Create `hosts/<name>/` with `default.nix`, `disko.nix`, and a placeholder
   `hardware-configuration.nix`, following `hosts/casper/`. Set
   `hostCategory = "desktop"` and register the host in `nixosConfigurations`.
2. Import `profiles/common.nix` + `profiles/secrets.nix`. For the desktop,
   either import `profiles/desktop.nix` (Plasma) or compose the granular
   profiles directly if you want a different environment:
   `profiles/graphical/*`, `profiles/audio/pipewire.nix`,
   `profiles/networking/networkmanager.nix`.
3. Only once the hardware is known: add a GPU profile (an AMD or Intel
   sibling of `profiles/nvidia.nix`) and a `profiles/laptop.nix` for power
   management, touchpad, and bluetooth.

### Hetzner VPS

1. Create `hosts/<name>/` importing `profiles/common.nix`,
   `profiles/secrets.nix`, and `profiles/server.nix`. Set
   `hostCategory = "server"`. No graphical/audio profiles.
2. Tailscale is already on by default (via `profiles/tailscale.nix`). With a
   `tailscale-auth-key` secret in sops, enrollment is unattended; otherwise
   run `sudo tailscale up` once. Then `ssh gabriel@<name>` works from any
   tailnet machine via MagicDNS.
3. Provision from your desktop with nixos-anywhere + disko against the rescue
   system. Later changes deploy over SSH:
   `nixos-rebuild switch --flake .#<name> --target-host gabriel@<name>`
   (or adopt colmena once there are several servers).
4. Serve content with the reverse-proxy module (nginx + ACME):

   ```nix
   imports = [ outputs.nixosModules.reverse-proxy ];

   services.reverseProxy = {
     enable = true;
     domain = "example.com";
     acmeEmail = "admin@example.com";
     apps.myapp = {
       subdomain = "app"; # -> app.example.com, proxied to 127.0.0.1:3000
       port = 3000;
       websockets = true; # optional
     };
   };
   ```

   DNS for each `<subdomain>.<domain>` must point at the host; ports 80/443
   are opened automatically for ACME HTTP-01.

### Secrets for a new host

Every host imports `profiles/secrets.nix` and shares `secrets/secrets.yaml`;
a new machine just becomes a recipient:

1. Derive the new host's age recipient from its SSH host key:
   `ssh gabriel@<name> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age`
2. Add it under `age:` in `.sops.yaml`, then rewrap the data key for it
   (YubiKey plugged in):
   ```sh
   nix develop -c sops updatekeys secrets/secrets.yaml
   ```
3. Deploy. The host decrypts with its own SSH host key; with the
   `tailscale-auth-key` secret present it also joins the tailnet unattended.

If a host ever needs secrets the others must not read, split a
`secrets/<name>.yaml` with its own `creation_rules` entry and point that host's
`sops.defaultSopsFile` at it — not needed while everything is shared.

## TODO before/after install

- [ ] Confirm the disk `device` in `hosts/casper/disko.nix` (use `by-id`).
- [ ] Replace `hosts/casper/hardware-configuration.nix` with the generated one.
- [x] Bootstrap sops (above); `gabriel`'s password now comes from the
      `gabriel-password` secret.
- [ ] Confirm timezone (`Europe/Lisbon`) and keyboard layout (`us`).
