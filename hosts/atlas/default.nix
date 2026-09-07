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

    inputs.hermes-agent.nixosModules.default
  ];

  # Upstream Cachix cache, currently unpopulated by their CI, kept so it just
  # works if that changes. hermes-agent is build-from-source until then.
  nix.settings = {
    extra-substituters = [ "https://hermes-agent.cachix.org" ];
    extra-trusted-public-keys = [
      "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
    ];
  };

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
    # Hermes Agent web dashboard.
    apps.hermes = {
      subdomain = "hermes";
      port = 9119;
      websockets = true;
    };
  };

  # Hermes Agent, Two hardened systemd units, both as the dedicated `hermes`
  # user (ProtectSystem=strict):
  #   hermes-agent    the messaging gateway (Telegram) + OpenAI-compatible API
  #   hermes-backend  the web dashboard
  # The agent runs arbitrary code as `hermes` and can reach every tailnet peer.
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true; # `hermes` CLI over SSH
    # Leave `package` at the default `full` build. Any extraDependencyGroups/
    # extraPythonPackages override re-invokes uv2nix and rebuilds everything.

    settings = {
      model.default = "openai/gpt-oss-120b";
      # A non-loopback public_url is what engages the dashboard auth gate and
      # makes its Host-header check accept requests forwarded by nginx.
      dashboard.public_url = "https://hermes.atlas.gabrielopesantos.com";
    };

    backend = {
      mode = "dashboard";
      host = "127.0.0.1"; # nginx fronts it
      port = 9119;
    };

    environmentFiles = [ config.sops.secrets.hermes-env.path ];
  };

  sops.secrets.hermes-env.owner = "hermes";

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
    paths = [
      "/var/lib/uptime-kuma"
      "/var/lib/hermes" # hermes-agent: sessions, memories, skills, .env
    ];
    healthchecksUrlFile = config.sops.secrets.healthchecks-url.path;
  };

  # The homepage module has no bind-address option; its Next.js server reads
  # HOSTNAME. Loopback-only so nothing can reach it except nginx on this host.
  systemd.services.homepage-dashboard.environment.HOSTNAME = "127.0.0.1";

  system.stateVersion = "25.11";
}
