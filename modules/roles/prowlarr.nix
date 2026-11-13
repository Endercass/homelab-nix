{
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 9696 ];

  virtualisation.oci-containers.containers.prowlarr = {
    image = "ghcr.io/hotio/prowlarr:latest";
    autoStart = true;
    ports = [ "9696:9696" ];
    volumes = [
      "/var/lib/prowlarr:/config"
    ];
    environment = {
      PUID = "0";
      PGID = "0";
      UMASK = "002";
      TZ = "UTC";
    };
  };
}
