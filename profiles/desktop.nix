# Workstation profile.
{ pkgs, ... }:
{
  # Display + session manager. SDDM running on Wayland.
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;

  # Keyboard layout (used by Plasma and the console).
  services.xserver.xkb = {
    layout = "us,pt";
    variant = ",";
  };

  # Desktop networking.
  networking.networkmanager.enable = true;

  # Audio via PipeWire (replaces PulseAudio).
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Make Electron/Chromium apps use Wayland natively.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  fonts.packages = with pkgs; [
    inter
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    liberation_ttf
    nerd-fonts.jetbrains-mono
    nerd-fonts.iosevka
  ];
}
