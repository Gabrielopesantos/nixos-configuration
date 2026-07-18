# KDE Plasma 6 on Wayland, with SDDM as the display manager.
{ ... }:
{
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;

  # Make Electron/Chromium apps use Wayland natively.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
