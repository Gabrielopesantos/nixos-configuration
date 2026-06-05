# casper - main workstation.
# AMD Ryzen 7 7700X + NVIDIA RTX 4070 SUPER, KDE Plasma 6 on Wayland.
{ inputs, ... }:
{
  imports = [
    # Generated on the target machine - see the file for instructions.
    ./hardware-configuration.nix

    # Declarative disk layout (consumed at install by `disko`).
    inputs.disko.nixosModules.disko
    ./disko.nix

    # nixos-hardware tuning. NOTE: no common-gpu-nvidia - that is the
    # PRIME/laptop variant; casper is a desktop driving its display off the
    # dGPU, so profiles/nvidia.nix handles the GPU instead.
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    # Shared base applied to every host.
    ../../profiles/common.nix

    # Secrets (sops-nix). Inert until bootstrapped - see profiles/secrets.nix.
    ../../profiles/secrets.nix

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
