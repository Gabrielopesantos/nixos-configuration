# Minimal hardware config for a Hetzner Cloud x86_64 VPS.
#
# fileSystems.* are intentionally omitted: disko generates them from disko.nix.
{ lib, ... }:
{
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "virtio_pci"
    "virtio_scsi"
    "virtio_net"
    "virtio_balloon"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # A single-public-IP cloud VM: DHCP on all interfaces is the right default.
  networking.useDHCP = lib.mkDefault true;
}
