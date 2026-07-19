# atlas - Hetzner Cloud VPS. Public Uptime Kuma via nginx reverse proxy;
# homepage-dashboard is tailnet-only via `tailscale serve`.
{ inputs, pkgs, ... }:
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

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "atlas,atlas.tailcadc07.ts.net,localhost:8082,127.0.0.1:8082";
    settings = {
      title = "atlas";
      theme = "dark";
      color = "slate";
    };
    widgets = [
      { resources = { cpu = true; memory = true; disk = "/"; }; }
      { search = { provider = "duckduckgo"; target = "_blank"; }; }
    ];
    services = [
      { Monitoring = [ { "Uptime Kuma" = { href = "https://kuma.gabrielopesantos.com"; description = "Status monitoring"; }; } ]; }
    ];
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

  # Homepage is private: published on the tailnet only, at
  # https://atlas.tailcadc07.ts.net (needs MagicDNS + HTTPS certs enabled in
  # the Tailscale admin console).
  systemd.services.tailscale-serve-homepage = {
    description = "Serve homepage-dashboard on the tailnet";
    after = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
    ];
    wants = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:8082";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
    };
  };

  system.stateVersion = "25.11";
}
