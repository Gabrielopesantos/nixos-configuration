# Headless profile for future servers / cloud dev machines.
# Import this INSTEAD OF desktop.nix on a server host:
#
#   imports = [ ./hardware-configuration.nix
#               ../../profiles/common.nix
#               ../../profiles/server.nix ];
#
# common.nix already enables hardened SSH; this profile just trims the rest.
{ lib, ... }:
{
  # No GUI: keep the closure small.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # Servers usually want predictable, declarative networking.
  # NetworkManager (desktop) is left off; configure per host as needed, e.g.
  #   networking.useNetworkd = true;

  # Reasonable headless default.
  services.qemuGuest.enable = lib.mkDefault true;
}
