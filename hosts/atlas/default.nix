# atlas - Hetzner Cloud VPS. All apps are fronted by the reverse-proxy
# module: Uptime Kuma is public (kuma.gabrielopesantos.com); everything else
# is tailnet-only at <app>.atlas.gabrielopesantos.com (wildcard DNS record
# pointing at the tailnet IP, wildcard cert via Cloudflare DNS-01).
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    inputs.disko.nixosModules.disko
    ./disko.nix

    ../../profiles/common.nix
    ../../profiles/secrets.nix
    ../../profiles/server.nix
    ../../profiles/swap.nix

    inputs.self.nixosModules.reverse-proxy
    inputs.self.nixosModules.backup
  ];

  networking.hostName = "atlas";
  hostCategory = "server";

  # SSH is tailnet-only: tailscale0 is a trusted interface (profiles/
  # tailscale.nix), so sshd stays reachable from the tailnet while port 22
  # is closed to the internet. Break-glass access: Hetzner web console.
  services.openssh.openFirewall = false;

  # Follow the repo unattended: pull main daily and rebuild. New nixpkgs only
  # arrives when flake.lock moves on main (weekly update-flake-lock PR, merged
  # by hand), so the human gate is the PR merge, not the deploy. Rollback
  # semantics apply: a failed build keeps the running system.
  system.autoUpgrade = {
    enable = true;
    flake = "github:gabrielopesantos/nixos-configuration";
    dates = "04:00";
    randomizedDelaySec = "20min";
    allowReboot = true; # kernel/systemd bumps need it to actually apply
    rebootWindow = {
      lower = "04:00";
      upper = "06:00";
    };
  };

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
    allowedHosts = "home.atlas.gabrielopesantos.com,localhost:8082,127.0.0.1:8082";
    settings = {
      title = "atlas";
      theme = "dark";
      color = "slate";
    };
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];
    services = [
      {
        Monitoring = [
          {
            "Uptime Kuma" = {
              href = "https://kuma.gabrielopesantos.com";
              description = "Status monitoring";
            };
          }
          {
            "gabrielopesantos" = {
              href = "https://gabrielopesantos.com";
              description = "My Personal Website";
            };
          }
        ];
      }
    ];
  };

  services.reverseProxy = {
    enable = true;
    domain = "gabrielopesantos.com";
    acmeEmail = "me@gabrielopesantos.com";
    private = {
      domain = "atlas.gabrielopesantos.com";
      address = "100.83.163.93"; # atlas's tailnet IP
      acmeEnvironmentFile = config.sops.secrets.cloudflare-acme-env.path;
    };
    apps.kuma = {
      subdomain = "kuma";
      port = 3001;
      websockets = true;
      public = true;
    };
    apps.homepage = {
      subdomain = "home";
      port = 8082;
    };
  };

  # Serve the static website on the apex domain.
  services.nginx.virtualHosts."gabrielopesantos.com" = {
    default = true;
    forceSSL = true;
    enableACME = true;
    serverAliases = [ "www.gabrielopesantos.com" ];
    root = "${inputs.website.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/website";
    locations."/" = {
      index = "index.html";
    };
  };

  # Cloudflare API token for the DNS-01 wildcard cert, as a lego env file:
  #   CLOUDFLARE_DNS_API_TOKEN=<token with Zone:DNS:Edit on gabrielopesantos.com>
  # MUST exist in secrets/secrets.yaml before this config is deployed.
  sops.secrets.cloudflare-acme-env = { };

  # Nightly restic backups of app state to Backblaze B2, heartbeat to
  # healthchecks.io (see modules/nixos/backup.nix for the secrets it needs).
  sops.secrets.healthchecks-url = { };
  services.backup = {
    enable = true;
    repository = "b2:santoslabs-atlas-backups:restic";
    paths = [ "/var/lib/uptime-kuma" ];
    healthchecksUrlFile = config.sops.secrets.healthchecks-url.path;
  };

  # The homepage module has no bind-address option; its Next.js server reads
  # HOSTNAME. Loopback-only so nothing can reach it except nginx on this host.
  systemd.services.homepage-dashboard.environment.HOSTNAME = "127.0.0.1";

  system.stateVersion = "25.11";
}
