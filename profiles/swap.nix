# Memory-pressure insurance: zram first, small disk swapfile as the floor.
# Opt-in per host (import it); neither disko layout carves a swap partition.
#
# zram (priority 5 by default) absorbs pressure with compressed RAM only;
# the swapfile (kernel default priority -2) is the emergency overflow so a
# build or runaway service gets slow instead of OOM-killed.
{ lib, ... }:
{
  zramSwap.enable = lib.mkDefault true;

  swapDevices = [
    {
      device = "/swapfile";
      size = 4096; # MiB; created automatically on activation
    }
  ];
}
