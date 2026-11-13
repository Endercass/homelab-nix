{
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 8989 ];

  virtualisation.oci-containers.containers.sonarr = {
    image = "ghcr.io/hotio/sonarr:latest";
    autoStart = true;
    ports = [ "8989:8989" ];
    volumes = [
      "/var/lib/sonarr:/config"
      "/media:/media:rslave"
    ];
    environment = {
      PUID = "0";
      PGID = "0";
      UMASK = "002";
      TZ = "UTC";
    };
  };
}
