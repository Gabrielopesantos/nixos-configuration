# NVIDIA proprietary driver, tuned for Wayland.
# casper has an RTX 4070 SUPER (Ada) — supports the open kernel modules.
{ config, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    # Required for Wayland (also sets nvidia-drm.modeset=1).
    modesetting.enable = true;

    # Ada-and-newer: use the open-source kernel modules (NVIDIA's recommended
    # path on these GPUs). Set to false if you hit regressions.
    open = true;

    # Installs the `nvidia-settings` control panel.
    nvidiaSettings = true;

    # VRAM preservation across suspend/resume. Required on this Wayland + dGPU
    # setup, otherwise kwin_wayland loses its GPU buffers on resume and crashes.
    # Enables NVreg_PreserveVideoMemoryAllocations=1 and the
    # nvidia-{suspend,resume,hibernate} systemd services.
    powerManagement.enable = true;

    # Production/stable driver branch. Could pin to .beta or .production.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
