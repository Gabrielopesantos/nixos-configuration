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
  common.nix                    # base: nix settings, gc, locale, keyboard, user gabriel, ssh
  tailscale.nix                 # tailnet membership, on by default (imported by common.nix)
  desktop.nix                   # meta-profile composing the granular desktop profiles below
  graphical/plasma.nix          # KDE Plasma 6 / Wayland, SDDM
  graphical/fonts.nix           # desktop font set
  audio/pipewire.nix            # PipeWire audio
  networking/networkmanager.nix # NetworkManager (desktops/laptops)
  nvidia.nix                    # NVIDIA proprietary driver, Wayland-tuned
  secrets.nix                   # sops-nix scaffold (inert until bootstrapped)
  server.nix                    # headless profile for future cloud/dev hosts
modules/nixos/                  # reusable modules (reverse-proxy; exported via flake)
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
- `sops-nix` - secrets, host-SSH-key backed (scaffolded, see [`docs/setup.md`](docs/setup.md)).

## Commands

```sh
sudo nixos-rebuild switch --flake .#casper   # apply changes
nix flake update                             # bump all inputs
nix flake check                              # evaluate everything
nix fmt                                      # format (nixfmt-rfc-style)
```

## License

MIT
