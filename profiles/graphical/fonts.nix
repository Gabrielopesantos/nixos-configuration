# Desktop font set.
{ pkgs, ... }:
{
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
