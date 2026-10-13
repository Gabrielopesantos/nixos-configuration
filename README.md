# NixOS configuration

Flake-based NixOS config. One host today, structured for more.

A host imports `hardware-configuration.nix` + `disko.nix` plus whichever profiles
apply. A desktop imports `desktop.nix` + `nvidia.nix`; a server imports `server.nix`.

The home-manager config for `gabriel` lives in a **separate repo** and is applied
standalone (`home-manager switch`); it is not wired into this flake.

## Inputs of note

- `nixpkgs` stable `nixos-25.11`; `nixpkgs-unstable` exposed as `pkgs.unstablePkgs`.
- `hardware` (nixos-hardware) - casper pulls `common-cpu-amd` + `common-pc-ssd`.
- `disko` - declarative partitioning, used at install.
- `sops-nix` - secrets, host-SSH-key backed (see [`docs/setup.md`](docs/setup.md)).

## Commands

```sh
sudo nixos-rebuild switch --flake .#casper   # apply changes
nix flake update                             # bump all inputs
nix flake check                              # evaluate everything
nix fmt                                      # format (nixfmt-rfc-style)
```

## License

MIT
