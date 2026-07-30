{
  config,
  lib,
  pkgs,
  ...
}: {
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkDefault "prohibit-password";
    openFirewall = true;
  };
}