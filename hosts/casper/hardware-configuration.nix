# PLACEHOLDER — DO NOT TRUST THESE VALUES.
#
# This file only exists so the flake evaluates before casper is installed.
# On the target machine, regenerate it for real:
#
#   # while booted in the NixOS installer, after mounting your root at /mnt:
#   sudo nixos-generate-config --root /mnt
#   # then copy /mnt/etc/nixos/hardware-configuration.nix over this file.
#
# (Bootloader config lives in ./default.nix, not here.)
{
  config,
  lib,
  ...
}:
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

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
