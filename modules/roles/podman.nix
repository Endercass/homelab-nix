{ ... } : {
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true; # provide /run/podman/podman.sock and docker-compatible socket
    defaultNetwork.settings.dns_enabled = true;
  };
}
