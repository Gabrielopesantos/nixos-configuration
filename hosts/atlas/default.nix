# atlas - Hetzner Cloud VPS
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
        Apps = [
          {
            "Trek" = {
              href = "https://trek.gabrielopesantos.com";
              description = "Trip planner";
              icon = "mdi-airplane";
              siteMonitor = "http://127.0.0.1:3000";
            };
          }
        ];
      }
      {
        Monitoring = [
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
    apps.homepage = {
      subdomain = "home";
      port = 8082;
    };
    apps.trek = {
      subdomain = "trek";
      port = 3000;
      websockets = true;
      public = true;
    };
  };

  # TREK's README calls for a higher upload limit (backup/import uploads);
  # the reverseProxy module only sets nginx's recommended defaults, so
  # extend its generated vhost here.
  services.nginx.virtualHosts."trek.gabrielopesantos.com".locations = {
    "/".extraConfig = "client_max_body_size 500m;";
    # MCP responses are Server-Sent Events: buffering must be off, and the
    # stream outlives nginx's default 60s read timeout.
    "/mcp" = {
      proxyPass = "http://127.0.0.1:3000";
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 1h;
      '';
    };
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # podman does not auto-create missing bind-mount host dirs (unlike
  # docker); without this the container fails with
  # "Error: statfs /var/lib/trek/data: no such file or directory".
  systemd.tmpfiles.rules = [
    "d /var/lib/trek 0750 root root -"
    "d /var/lib/trek/data 0750 root root -"
    "d /var/lib/trek/uploads 0750 root root -"
  ];

  virtualisation.oci-containers.containers.trek = {
    image = "mauriceboe/trek:5.1.0";
    # loopback-only publish: podman can insert iptables rules that bypass
    # the NixOS firewall, see modules/nixos/reverse-proxy.nix header.
    ports = [ "127.0.0.1:3000:3000" ];
    volumes = [
      "/var/lib/trek/data:/app/data"
      "/var/lib/trek/uploads:/app/uploads"
    ];
    # OAuth issuer for MCP; must be the public https origin.
    environment.APP_URL = "https://trek.gabrielopesantos.com";
    environmentFiles = [ config.sops.secrets.trek-env.path ];
  };

  # ENCRYPTION_KEY=<openssl rand -hex 32>
  # MUST exist in secrets/secrets.yaml before this config is deployed.
  sops.secrets.trek-env = { };

  # healthchecks.io ping URL (no trailing /fail) for the backup heartbeat.
  # MUST exist in secrets/secrets.yaml before this config is deployed.
  sops.secrets.healthchecks-url = { };

  services.backup = {
    enable = true;
    paths = [ "/var/lib/trek" ];
    healthchecksUrlFile = config.sops.secrets.healthchecks-url.path;
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

  # The homepage module has no bind-address option; its Next.js server reads
  # HOSTNAME. Loopback-only so nothing can reach it except nginx on this host.
  systemd.services.homepage-dashboard.environment.HOSTNAME = "127.0.0.1";

  system.stateVersion = "25.11";
}
