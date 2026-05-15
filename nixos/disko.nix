{lib, ...}: let
  generated = builtins.fromJSON (builtins.readFile ./generated-config.json);
in {
  disko.devices = {
    disk.main = {
      device = lib.mkDefault (generated.disk.device or "/dev/sda");
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            end = "513MiB";
            name = "ESP";
            start = "1MiB";
            type = "EF00";

            content = {
              format = "vfat";
              mountOptions = ["umask=0077"];
              mountpoint = "/boot";
              type = "filesystem";
            };
          };

          root = {
            name = "root";
            size = "100%";

            content = {
              format = "ext4";
              mountpoint = "/";
              type = "filesystem";
            };
          };
        };
      };
    };
  };
}
