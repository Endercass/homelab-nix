{
  config,
  lib,
  ...
}:
{
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  users.users.root.extraGroups = [ "docker" ];
  virtualisation.docker.daemon.settings = {
    dns = [
      "100.100.100.100"
      "1.1.1.1"
    ];
  };
}
