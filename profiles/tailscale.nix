# Tailscale mesh VPN. Imported by common.nix so every host joins the tailnet
# by default. A host can opt out with:
#
#   services.tailscale.enable = false;
#
# Unattended enrollment: once sops is bootstrapped (see profiles/secrets.nix),
# declaring a `tailscale-auth-key` secret makes new machines join the tailnet
# automatically via services.tailscale.authKeyFile.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.tailscale = {
    enable = lib.mkDefault true;
    # Allow tailnet traffic in; the firewall stays closed otherwise.
    openFirewall = true;
  }
  // lib.optionalAttrs ((config.sops.secrets or { }) ? tailscale-auth-key) {
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
  };

  # Single-person tailnet: treat it like a LAN. Lets tailnet peers reach any
  # local service (SSH, private nginx vhosts) without per-port firewall holes.
  networking.firewall.trustedInterfaces = lib.mkIf config.services.tailscale.enable [
    config.services.tailscale.interfaceName
  ];

  # CLI on machines that actually run tailscaled.
  environment.systemPackages = lib.optional config.services.tailscale.enable pkgs.tailscale;
}
