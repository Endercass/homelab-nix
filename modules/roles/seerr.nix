{
  config,
  ...
}: {
  networking.firewall.allowedTCPPorts = [5055];

  virtualisation.oci-containers.containers.seerr = {
    image = "seerr/seerr:latest";
    autoStart = true;
    ports = [ "5055:5055" ];
    volumes = [
      "/var/lib/seerr:/app/config"
    ];
    environment = {
      LOG_LEVEL = "info";
      TZ = "UTC";
    };
  };
}
