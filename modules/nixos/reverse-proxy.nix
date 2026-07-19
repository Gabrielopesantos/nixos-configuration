# Reverse proxy for workload servers: declare an app with a subdomain and a
# localhost port, and this module fronts it with an nginx vhost (HTTPS via
# ACME/Let's Encrypt).
#
# Apps are PRIVATE by default: served at <subdomain>.<private.domain> (a
# host-scoped zone, e.g. app.atlas.example.com), bound to the tailnet IP only,
# with a wildcard cert obtained via DNS-01 — unreachable from the internet
# even though public DNS resolves the name. Set `public = true` on an app to
# expose it at <subdomain>.<domain> on the public interface instead.
#
# Usage on a host:
#
#   imports = [ outputs.nixosModules.reverse-proxy ];
#
#   services.reverseProxy = {
#     enable = true;
#     domain = "example.com";
#     acmeEmail = "admin@example.com";
#     private = {
#       domain = "atlas.example.com";     # apps at <sub>.atlas.example.com
#       address = "100.x.y.z";            # this host's tailnet IP
#       # env file with CLOUDFLARE_DNS_API_TOKEN=... for lego DNS-01
#       acmeEnvironmentFile = config.sops.secrets.cloudflare-acme-env.path;
#     };
#     apps.myapp = {
#       subdomain = "app";        # -> app.atlas.example.com (private)
#       port = 3000;              # process listening on address:port
#       websockets = true;        # optional, default false
#     };
#     apps.status = {
#       subdomain = "status";     # -> status.example.com (public)
#       port = 3001;
#       public = true;
#     };
#   };
#
# DNS: public apps need <subdomain>.<domain> pointing at the host's public
# IP; private apps are covered by one wildcard record *.<private.domain>
# pointing at the tailnet IP. Ports 80/443 must be publicly reachable for
# ACME HTTP-01 validation of public apps.
#
# Security note: the app process must bind to `address` only, not the wildcard
# address. For OCI containers (Docker/Podman), publish the port as
# "127.0.0.1:3000:3000" rather than "3000:3000", because container runtimes
# can insert iptables rules that bypass the NixOS firewall.

{ config, lib, ... }:
let
  cfg = config.services.reverseProxy;

  appOpts = {
    options = {
      subdomain = lib.mkOption {
        type = lib.types.str;
        description = "Subdomain for this app, under services.reverseProxy.domain (public) or .private.domain (private).";
        example = "app";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address the app process listens on. Use 127.0.0.1 (the default) for loopback-only apps; set to a container/network IP if the app is not running directly on the host.";
        example = "127.0.0.1";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Port on `address` the app process listens on.";
        example = 3000;
      };

      websockets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the app needs WebSocket proxying.";
      };

      public = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose this app on the public interface at <subdomain>.<domain>. Default is private: tailnet-only at <subdomain>.<private.domain>.";
      };
    };
  };

  publicApps = lib.filterAttrs (_: app: app.public) cfg.apps;
  privateApps = lib.filterAttrs (_: app: !app.public) cfg.apps;
  hasPrivateApps = privateApps != { };
in
{
  options.services.reverseProxy = {
    enable = lib.mkEnableOption "nginx reverse proxy for local apps";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain; public apps are served at <subdomain>.<domain>.";
      example = "example.com";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact email for ACME (Let's Encrypt) account registration.";
      example = "admin@example.com";
    };

    private = {
      domain = lib.mkOption {
        type = lib.types.str;
        description = "Host-scoped zone for private apps, served at <subdomain>.<private.domain>. A wildcard cert *.<private.domain> is obtained via DNS-01.";
        example = "atlas.example.com";
      };

      address = lib.mkOption {
        type = lib.types.str;
        description = "Tailnet IP of this host; private vhosts bind to it exclusively, so they are unreachable via the public interface.";
        example = "100.64.0.1";
      };

      acmeEnvironmentFile = lib.mkOption {
        type = lib.types.path;
        description = "EnvironmentFile with credentials for the lego Cloudflare DNS-01 provider (CLOUDFLARE_DNS_API_TOKEN=...). Keep it in sops.";
      };
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule appOpts);
      default = { };
      description = "Apps to expose, keyed by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts =
        lib.mapAttrs' (
          _: app:
          lib.nameValuePair "${app.subdomain}.${cfg.domain}" {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://${app.address}:${toString app.port}";
              proxyWebsockets = app.websockets;
            };
          }
        ) publicApps
        // lib.mapAttrs' (
          _: app:
          lib.nameValuePair "${app.subdomain}.${cfg.private.domain}" {
            forceSSL = true;
            useACMEHost = cfg.private.domain;
            listenAddresses = [ cfg.private.address ];
            locations."/" = {
              proxyPass = "http://${app.address}:${toString app.port}";
              proxyWebsockets = app.websockets;
            };
          }
        ) privateApps;
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;

      # One wildcard cert covers every private vhost; DNS-01 keeps app names
      # out of certificate-transparency logs and needs no public port 80.
      certs = lib.mkIf hasPrivateApps {
        ${cfg.private.domain} = {
          domain = "*.${cfg.private.domain}";
          dnsProvider = "cloudflare";
          environmentFile = cfg.private.acmeEnvironmentFile;
          group = "nginx";
        };
      };
    };

    # Private vhosts bind the tailnet IP, which may not exist yet when nginx
    # starts (tailscaled races nginx at boot). Allow binding regardless.
    boot.kernel.sysctl = lib.mkIf hasPrivateApps {
      "net.ipv4.ip_nonlocal_bind" = true;
    };

    networking.firewall.allowedTCPPorts = [
      80 # ACME HTTP-01 + redirect to HTTPS
      443
    ];

    warnings = lib.optionals cfg.enable (
      let
        exposed = lib.filter (
          name: lib.elem cfg.apps.${name}.port config.networking.firewall.allowedTCPPorts
        ) (lib.attrNames cfg.apps);
      in
      lib.map (
        name:
        "reverseProxy apps.${name} port ${toString cfg.apps.${name}.port} is also opened in the firewall; the app should be reachable only via the reverse proxy"
      ) exposed
    );
  };
}
