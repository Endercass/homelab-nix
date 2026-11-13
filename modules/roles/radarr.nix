{
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 7878 ];

  virtualisation.oci-containers.containers.radarr = {
    image = "ghcr.io/hotio/radarr:latest";
    autoStart = true;
    ports = [ "7878:7878" ];
    volumes = [
      "/var/lib/radarr:/config"
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
