# Declarative disk layout for casper.
#
# Applied at install time, NOT on every rebuild:
#   sudo nix run github:nix-community/disko/latest -- \
#     --mode destroy,format,mount --flake .#casper /mnt
#
# disko generates the `fileSystems.*` entries, so they must NOT also be set in
# hardware-configuration.nix.
#
# Single NVMe, GPT: 1G EFI System Partition + ext4 root. No swap partition
# (use zram or a swapfile if needed).
{
  disko.devices.disk.main = {
    type = "disk";
    # TODO: confirm on the machine. Prefer a stable /dev/disk/by-id/... path
    # (run `ls -l /dev/disk/by-id` in the installer) over /dev/nvme0n1.
    device = "/dev/nvme1n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "1G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
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
