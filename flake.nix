{
  description = "NixOS configuration (casper + future hosts)";

  inputs = {
    # Stable channel - the default for all hosts.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Unstable, exposed as 'pkgs.unstablePkgs' via overlays/default.nix
    # for the occasional bleeding-edge package.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

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

      # `nix fmt`
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      # Custom packages/modifications exported as overlays.
      overlays = import ./overlays { inherit inputs; };

      # Reusable NixOS modules (stuff you might upstream).
      nixosModules = import ./modules/nixos;

      # NixOS hosts. Build/switch with:
      #   sudo nixos-rebuild switch --flake .#casper
      nixosConfigurations = {
        casper = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/casper
          ];
        };

        # Future hosts go here, e.g.:
        # cloud-dev = nixpkgs.lib.nixosSystem {
        #   specialArgs = {inherit inputs;};
        #   modules = [ ./hosts/cloud-dev ];
        # };
      };
    };
}
