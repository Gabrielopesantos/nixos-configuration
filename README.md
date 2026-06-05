# NixOS configuration

Flake-based NixOS config. One host today, structured for more.

## Layout

```
flake.nix                       # inputs + nixosConfigurations
hosts/
  casper/
    default.nix                 # host: hostname, bootloader, imports its profiles
    disko.nix                   # declarative disk layout (install-time)
    hardware-configuration.nix  # PLACEHOLDER - regenerate on the machine
profiles/
  common.nix                    # base: nix settings, gc, locale, user gabriel, ssh, fonts
  desktop.nix                   # KDE Plasma 6 / Wayland, PipeWire, NetworkManager
  nvidia.nix                    # NVIDIA proprietary driver, Wayland-tuned
  secrets.nix                   # sops-nix scaffold (inert until bootstrapped)
  server.nix                    # headless profile for future cloud/dev hosts
modules/nixos/                  # reusable modules (exported via flake)
overlays/                       # custom pkgs + `pkgs.unstablePkgs` from nixpkgs-unstable
pkgs/                           # custom package definitions
.sops.yaml                      # secrets recipients + creation rules
```

A host imports `hardware-configuration.nix` + `disko.nix` plus whichever profiles
apply. A desktop imports `desktop.nix` + `nvidia.nix`; a server imports `server.nix`.

The home-manager config for `gabriel` lives in a **separate repo** and is applied
standalone (`home-manager switch`); it is not wired into this flake.

## Inputs of note

- `nixpkgs` stable `nixos-25.11`; `nixpkgs-unstable` exposed as `pkgs.unstablePkgs`.
- `hardware` (nixos-hardware) - casper pulls `common-cpu-amd` + `common-pc-ssd`.
- `disko` - declarative partitioning, used at install.
- `sops-nix` - secrets, host-SSH-key backed (scaffolded, see below).

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

## TODO before/after install

- [ ] Confirm the disk `device` in `hosts/casper/disko.nix` (use `by-id`).
- [ ] Replace `hosts/casper/hardware-configuration.nix` with the generated one.
- [ ] Add SSH public key(s) in `profiles/common.nix`.
- [ ] Bootstrap sops (above), then move `gabriel`'s password off `initialPassword`.
- [ ] Confirm timezone (`Europe/Lisbon`) and keyboard layout (`us`).
