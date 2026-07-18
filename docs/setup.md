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
6. Reboot. Log in as `gabriel` (initial password `changeme` - change with
   `passwd`). Then commit the real `hardware-configuration.nix`.

## Secrets bootstrap (after first boot)

`profiles/secrets.nix` is wired but inert until you provide keys. Two recipients:
your **YubiKey GPG key** (you, the editor) and **casper's host SSH key as age** (the
machine, unattended).

1. Personal identity = the YubiKey. Confirm the card and copy your key fingerprint
   into `.sops.yaml` as the `pgp` recipient (gabriel):
   ```sh
   gpg --card-status        # YubiKey is seen
   gpg -K --with-colons     # grab the fpr line
   ```
2. casper's machine identity = its SSH host key, as age. Add it as the `age`
   recipient in `.sops.yaml`:
   ```sh
   nix run nixpkgs#ssh-to-age -- < /etc/ssh/ssh_host_ed25519_key.pub
   ```
   (`sops`/`gpg-agent` with the YubiKey must be available when you edit secrets.)
3. Create the encrypted store and add `gabriel-password` (a `mkpasswd -m yescrypt` hash):
   ```sh
   sops secrets/secrets.yaml
   ```
4. In `profiles/secrets.nix`: set `validateSopsFiles = true`, uncomment
   `defaultSopsFile` and the `gabriel-password` secret.
5. In `profiles/common.nix`: replace `initialPassword` with
   `hashedPasswordFile = config.sops.secrets.gabriel-password.path;`. Rebuild.

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

### Secrets per host

Each machine decrypts only its own secrets, using its own SSH host key:

1. Derive the new host's age recipient:
   `ssh gabriel@<name> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age`
2. Add it as a recipient in `.sops.yaml`, then create `secrets/<name>.yaml`
   encrypted to that recipient + your GPG key.
3. In the host's config: `sops.defaultSopsFile = ../../secrets/<name>.yaml;`
   and declare the secrets it needs.

## TODO before/after install

- [ ] Confirm the disk `device` in `hosts/casper/disko.nix` (use `by-id`).
- [ ] Replace `hosts/casper/hardware-configuration.nix` with the generated one.
- [ ] Bootstrap sops (above), then move `gabriel`'s password off `initialPassword`.
- [ ] Confirm timezone (`Europe/Lisbon`) and keyboard layout (`us`).
