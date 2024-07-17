{ ... }:
let
  mirrorBoot = idx: {
    type = "disk";
    device = "/dev/nvme${idx}n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot${idx}";
          };
        };
        zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "zroot";
          };
        };
      };
    };
  };
in
{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [
      {
        path = "/boot0";
        devices = [ "nodev" ];
      }
      {
        path = "/boot1";
        devices = [ "nodev" ];
      }
    ];
  };

  disko.devices = {
    disk = {
      x = mirrorBoot "0";
      y = mirrorBoot "1";
    };

    zpool = {
      zroot = {
        type = "zpool";
        options.ashift = "12";

        # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
        rootFsOptions = {
          compression = "lz4";
          xattr = "sa";
          relatime = "on";
          acltype = "posixacl";
          "com.sun:auto-snapshot" = "false";
        };

        datasets = {
          "root" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "root/nixos" = {
            type = "zfs_fs";
            options.mountpoint = "/";
            mountpoint = "/";
            options."com.sun:auto-snapshot" = "true";
          };

          "root/tmp" = {
            type = "zfs_fs";
            mountpoint = "/tmp";
            options.sync = "disabled";
          };
        };
      };
    };
  };
}
