# Desktop networking: NetworkManager, for Wi-Fi roaming and GUI/VPN
# integration. Servers should use declarative networking instead
# (see profiles/server.nix).
{ ... }:
{
  networking.networkmanager.enable = true;
}
