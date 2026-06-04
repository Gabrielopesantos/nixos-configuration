# NixOS configuration

Flake-based NixOS config.

## Layout

```
flake.nix              # inputs + nixosConfigurations
hosts/
  casper/
    default.nix              # host: hostname, bootloader, imports its profiles
    hardware-configuration.nix  # PLACEHOLDER — regenerate on the machine
profiles/
  common.nix           # base: nix settings, gc, locale, user gabriel, ssh, fonts
  desktop.nix          # KDE Plasma 6 / Wayland, PipeWire, NetworkManager
  nvidia.nix           # NVIDIA proprietary driver, Wayland-tuned
  server.nix           # headless profile for future cloud/dev hosts
modules/nixos/         # reusable modules (exported via flake)
overlays/              # custom pkgs + `pkgs.unstablePkgs` from nixpkgs-unstable
pkgs/                  # custom package definitions
```

A host imports `hardware-configuration.nix` plus whichever profiles apply.
A desktop imports `desktop.nix` + `nvidia.nix`; a server imports `server.nix`
instead.

The home-manager config for `gabriel` lives in a **separate repo** and is
applied standalone (`home-manager switch`); it is not wired into this flake.

## Channel

Stable `nixos-25.11`. `nixpkgs-unstable` is available as `pkgs.unstablePkgs`
for individual bleeding-edge packages without moving the whole system.

## First install on casper (fresh ISO)

To switch it to NixOS:

1. Write the NixOS ISO to USB, boot it.
2. Partition + format (GPT, an EFI `/boot` vfat + a root). Label them so the
   placeholder fstab matches, or edit it after:
   ```sh
   # example — adjust devices
   mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
   mkfs.ext4 -L nixos /dev/nvme0n1p2
   mount /dev/disk/by-label/nixos /mnt
   mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
   ```
3. Generate the real hardware config and copy it over the placeholder:
   ```sh
   sudo nixos-generate-config --root /mnt
   # copy /mnt/etc/nixos/hardware-configuration.nix into
   # this repo at hosts/casper/hardware-configuration.nix
   ```
4. Install from the flake:
   ```sh
   sudo nixos-install --flake <path-to-repo>#casper
   ```
5. Reboot. Log in as `gabriel` (initial password `changeme` — change it with
   `passwd`). Add your SSH key in `profiles/common.nix` and your real
   `hardware-configuration.nix`, then commit.

## Day-to-day

```sh
sudo nixos-rebuild switch --flake .#casper   # apply changes
nix flake update                              # bump all inputs
nix flake check                               # evaluate everything
nix fmt                                       # format with alejandra
```

## TODO before/after install

- [ ] Replace `hosts/casper/hardware-configuration.nix` with the generated one.
- [ ] Add SSH public key(s) in `profiles/common.nix`.
- [ ] Change `gabriel`'s password (or switch `initialPassword` →
      `hashedPassword`).
- [ ] Confirm timezone (`Europe/Lisbon`) and keyboard layout (`us`).
- [ ] Secrets management for servers (sops-nix or agenix) when you add hosts.
