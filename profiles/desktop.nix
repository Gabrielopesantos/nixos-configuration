# Workstation profile: full graphical desktop.
# Composes the granular graphical/audio/networking profiles. A host that wants
# a different mix (e.g. a laptop with another desktop environment) can import
# those profiles directly instead of this file.
{ ... }:
{
  imports = [
    ./graphical/plasma.nix
    ./graphical/fonts.nix
    ./audio/pipewire.nix
    ./networking/networkmanager.nix
  ];
}
