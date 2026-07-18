# Declarative disk layout for atlas (Hetzner Cloud VPS, legacy BIOS).
#
# Hetzner Cloud VMs boot via SeaBIOS, not UEFI, so we use a GPT with a
# BIOS boot partition (type EF02) rather than an ESP. Applied destructively at
# install time by nixos-anywhere + disko.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
          priority = 0;
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
