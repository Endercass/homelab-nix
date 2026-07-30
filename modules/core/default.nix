{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./nix.nix
    ./boot.nix
    ./security.nix
  ];

  networking.domain = lib.mkDefault "homelab.endercass.me";
}