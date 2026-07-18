# atlas - Hetzner Cloud VPS. Public Uptime Kuma via nginx reverse proxy.
{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix

    inputs.disko.nixosModules.disko
    ./disko.nix

    ../../profiles/common.nix
    ../../profiles/secrets.nix
    ../../profiles/server.nix

    inputs.self.nixosModules.reverse-proxy
  ];

  networking.hostName = "atlas";
  hostCategory = "server";

  # Hetzner Cloud VMs are legacy BIOS only. The EF02 partition in disko.nix
  # automatically sets boot.loader.grub.devices; do not set boot.loader.grub.device
  # here or it will be duplicated.
  boot.loader.grub = {
    efiSupport = false;
    useOSProber = false;
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };

  services.reverseProxy = {
    enable = true;
    domain = "gabrielopesantos.com";
    acmeEmail = "me@gabrielopesantos.com";
    apps.kuma = {
      subdomain = "kuma";
      port = 3001;
      websockets = true;
    };
  };

  system.stateVersion = "25.11";
}
