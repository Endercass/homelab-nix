{
  config,
  lib,
  pkgs,
  ...
}: {
  boot.initrd.kernelModules = ["dm-snapshot" "cryptd"];
  boot.initrd.services.lvm.enable = true;
}
