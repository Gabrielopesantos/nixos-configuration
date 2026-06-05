{
  description = "NixOS configuration (casper + future hosts)";

  inputs = {
    # Stable channel - the default for all hosts.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Unstable, exposed as 'pkgs.unstablePkgs' via overlays/default.nix
    # for the occasional bleeding-edge package.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Per-device tuning modules (CPU/SSD/GPU profiles).
    hardware.url = "github:NixOS/nixos-hardware";

    # Declarative disk partitioning (used at install time).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management (sops + age, host-key backed).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOTE: home-manager is intentionally NOT an input here.
    # The user environment for 'gabriel' lives in a separate repo and is
    # applied standalone with `home-manager switch`.
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      # Passed into modules alongside `inputs` so they can reach this flake's
      # own overlays/packages/modules without a `self` round-trip.
      outputs = self;

      # Systems we build packages/formatter for. Includes aarch64 for future
      # ARM cloud hosts.
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Custom packages, accessible through 'nix build', 'nix shell', etc.
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      # `nix fmt` - matches the nixfmt RFC style used to edit this repo.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # `nix develop` (auto-entered via .envrc/direnv). Tools for hacking on
      # this repo: formatting + secrets management.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt-rfc-style # `nix fmt`
              sops # edit secrets/*.yaml
              gnupg # YubiKey GPG backing for sops (personal recipient)
              age # age key management
              ssh-to-age # derive an age key from an ssh host key
              git
            ];
          };
        }
      );

      # Custom packages/modifications exported as overlays.
      overlays = import ./overlays { inherit inputs; };

      # Reusable NixOS modules (stuff you might upstream).
      nixosModules = import ./modules/nixos;

      # NixOS hosts. Build/switch with:
      #   sudo nixos-rebuild switch --flake .#casper
      nixosConfigurations = {
        casper = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./hosts/casper
          ];
        };

        # Future hosts go here, e.g.:
        # cloud-dev = nixpkgs.lib.nixosSystem {
        #   specialArgs = { inherit inputs outputs; };
        #   modules = [ ./hosts/cloud-dev ];
        # };
      };
    };
}
