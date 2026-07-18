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
#       port = 3000;              # process listening on 127.0.0.1:3000
#       websockets = true;        # optional, default false
#     };
#   };
#
# DNS for each <subdomain>.<domain> must point at the host, and ports 80/443
# must be reachable for ACME HTTP-01 validation.
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

      port = lib.mkOption {
        type = lib.types.port;
        description = "Localhost port the app process listens on.";
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
            proxyPass = "http://127.0.0.1:${toString app.port}";
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
  };
}
