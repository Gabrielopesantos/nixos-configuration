# PLACEHOLDER — DO NOT TRUST THESE VALUES.
#
# This file only exists so the flake evaluates before casper is installed.
# On the target machine, regenerate it for real:
#
#   # in the NixOS installer, after `disko ... --mode ...,mount /mnt`:
#   sudo nixos-generate-config --no-filesystems --root /mnt
#   # then copy /mnt/etc/nixos/hardware-configuration.nix over this file.
#
# --no-filesystems is important: disko (hosts/casper/disko.nix) owns the
# `fileSystems.*` entries, so they must NOT be duplicated here.
# Bootloader config lives in ./default.nix; AMD microcode is handled by the
# nixos-hardware common-cpu-amd module imported in ./default.nix.
{ ... }:
{
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  swapDevices = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
