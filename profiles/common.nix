# Shared base for every host (workstation or server).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./tailscale.nix ];

  # Machine type, set by each host. Shared modules can gate behavior on it
  # with `lib.mkIf (config.hostCategory == "server")`.
  options.hostCategory = lib.mkOption {
    type = lib.types.enum [
      "desktop"
      "server"
    ];
    description = "The type of host this configuration is for.";
  };

  config = {
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
        options = "--delete-older-than 7d";
      };
    };

    # Locale / time. mkDefault so a host can override.
    time.timeZone = lib.mkDefault "Europe/Lisbon";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    # Keyboard layout (used by graphical sessions and the console). mkDefault
    # so a host can override.
    services.xserver.xkb = lib.mkDefault {
      layout = "us,pt";
      variant = ",";
    };

    # Users are fully declarative: passwords come from config on every
    # activation, `passwd` on the host has no lasting effect.
    users.mutableUsers = false;

    # Single admin user. Present on every host so you can SSH into servers too.
    users.users.gabriel = {
      isNormalUser = true;
      description = "Gabriel Santos";
      # yescrypt hash in sops (`mkpasswd -m yescrypt`, key gabriel-password).
      hashedPasswordFile = config.sops.secrets.gabriel-password.path;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      shell = pkgs.fish;
      # YubiKey GPG authentication subkey, exported with `gpg --export-ssh-key`.
      # Private material never leaves the YubiKey.
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDEeBzBw7K1cJRctYVMCvUANZLYNHd+6wkIR5AmHpvSZ5oiLGYREKKsGxws5VXEZ65XrbB9XEQH9vxxuWiUOgJNn7JmqkP3smWGp6g46NzKuSOc91N1OpjpVLpP5Sdpx9aPYuQ0M/mpHEjZF7cnZJOHLTXPU9FLwfjxuDYTR1tdKP9lu/B41FSs2GTLEDfQmgUJM71Rkh4Uh8qBsoOW/cxDgkGr8ChL0mpxv6WX8AzgOLqDMy2KW7QJZT4j9eHIBOI1RsP8Qr0bp/WbXb+vI72SVr/57RC2w86VvKTKDj095x3snVir6oH4e9oZQagT9XCzGA2ob1M/4Bhuy1x3F1E/uDDVALZeQy4fOf8C9pl1vf1+BIu/BnhgpTPlYXj4gkb7LzOIv35tZseau1xtk56nvv0vJDpfSzy1hJAN1yvy2/eNSj11soHAEr3ovJthvl0tHqiboQCfk+nZzKdXzB9foccfof93UJ4/RUmG8Ra7Yr/qhRrfp4FwswJe2+OPjweRoRE7x5O5q0rWnBcNexkJlIH95Q39ROJodsJHoCjykArp/J9+2u99eMH2/5ZP9BBZHZwwGq3fQ+PSNOKrlxZYv0kNRZiwNpl23/N8cAsIif3laMR3nRR1xQkvPnDjuMQ38OnhYT9DYfbXAzw6m/M2nSQzDLw5ss64Lj01kq0P1Q== openpgp:0x4E3F4B50"
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
  };
}
