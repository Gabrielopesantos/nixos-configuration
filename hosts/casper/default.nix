# casper - main workstation.
{ ... }:
{
  imports = [
    # Generated on the target machine - see the file for instructions.
    ./hardware-configuration.nix

    # Shared base applied to every host.
    ../../profiles/common.nix

    # Workstation profile.
    ../../profiles/desktop.nix

    # NVIDIA proprietary driver tuned for Wayland.
    ../../profiles/nvidia.nix
  ];

  networking.hostName = "casper";

  # Bootloader. nixos-generate-config does NOT manage this, so it lives here.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Do not change after install - see
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
