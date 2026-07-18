# Reverse proxy for workload servers: declare an app with a subdomain and a
# localhost port, and this module fronts it with an nginx vhost (HTTPS via
# ACME/Let's Encrypt).
#
# Usage on a host:
#
#   imports = [ outputs.nixosModules.reverse-proxy ];
#
#   services.reverseProxy = {
#     enable = true;
#     domain = "example.com";
#     acmeEmail = "admin@example.com";
#     apps.myapp = {
#       subdomain = "app";        # -> app.example.com
#       address = "127.0.0.1";    # optional, default 127.0.0.1
#       port = 3000;              # process listening on address:port
#       websockets = true;        # optional, default false
#     };
#   };
#
# DNS for each <subdomain>.<domain> must point at the host, and ports 80/443
# must be reachable for ACME HTTP-01 validation.
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
        description = "Subdomain under services.reverseProxy.domain for this app.";
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
    };
  };
in
{
  options.services.reverseProxy = {
    enable = lib.mkEnableOption "nginx reverse proxy for local apps";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain; apps are served at <subdomain>.<domain>.";
      example = "example.com";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact email for ACME (Let's Encrypt) account registration.";
      example = "admin@example.com";
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

      virtualHosts = lib.mapAttrs' (
        _: app:
        lib.nameValuePair "${app.subdomain}.${cfg.domain}" {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://${app.address}:${toString app.port}";
            proxyWebsockets = app.websockets;
          };
        }
      ) cfg.apps;
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
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
