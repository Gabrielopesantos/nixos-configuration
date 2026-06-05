# Shared base for every host (workstation or server).
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  nixpkgs = {
    overlays = [
      inputs.self.overlays.additions
      inputs.self.overlays.modifications
      inputs.self.overlays.unstable-packages
    ];
    # NVIDIA and friends are unfree.
    config.allowUnfree = true;
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Opinionated: drop the global registry/channels in favour of the flake.
      flake-registry = "";
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "gabriel"
      ];
    };
    channel.enable = false;

    # Pin <nixpkgs> and the flake registry to the exact nixpkgs this system
    # was built from, so ad-hoc `nix shell nixpkgs#foo` matches the system.
    registry.nixpkgs.flake = inputs.nixpkgs;
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Locale / time. mkDefault so a host can override.
  time.timeZone = lib.mkDefault "Europe/Lisbon";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Single admin user. Present on every host so you can SSH into servers too.
  users.users.gabriel = {
    isNormalUser = true;
    description = "Gabriel Santos";
    # Bootstrap password for the first boot. After sops-nix is wired
    # (see profiles/secrets.nix), replace this with:
    #   hashedPasswordFile = config.sops.secrets.gabriel-password.path;
    # and delete initialPassword.
    initialPassword = "changeme";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      # TODO: add your SSH public key(s), e.g. "ssh-ed25519 AAAA... gabriel"
    ];
  };
  # fish is gabriel's login shell; the system needs it enabled to register it.
  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = true;

  # Headless-safe SSH defaults; harmless on the desktop.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  networking.firewall.enable = true;

  # Minimal base toolset. Per-user tooling belongs in the home-manager repo.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    htop
  ];
}
