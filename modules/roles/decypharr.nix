{
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 8282 ];
  systemd.tmpfiles.rules = [
    "d+ /media/arr/decypharr 0777 root root -"
  ];

  virtualisation.oci-containers.containers.tailscale-decypharr = {
    image = "tailscale/tailscale:stable";
    autoStart = true;
    ports = [ "8282:8282" ];
    volumes = [
      "/var/lib/tailscale-decypharr:/var/lib/tailscale"
      "${config.sops.secrets."headscale-preauthkey".path}:/run/secrets/headscale-preauthkey:ro"
    ];
    cmd = [
      "sh"
      "-c"
      ''
        ln -sf /usr/sbin/iptables-nft /usr/sbin/iptables
        tailscaled --state=/var/lib/tailscale/tailscaled.state &
        until tailscale up \
          --login-server=https://headscale.endercass.me \
          --accept-dns=false \
          --auth-key="$(cat /run/secrets/headscale-preauthkey)" \
          --hostname=decypharr \
          --exit-node=relay \
          --netfilter-mode=on
        do
          sleep 5
        done
        wait
      ''
    ];
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--cap-add=NET_RAW"
      "--device=/dev/net/tun:/dev/net/tun"
    ];
  };

  virtualisation.oci-containers.containers.decypharr = {
    image = "cy01/blackhole:latest";
    autoStart = true;
    dependsOn = [ "tailscale-decypharr" ];
    volumes = [
      "/var/lib/decypharr:/app"
      "/media:/mnt:rshared"
      "/media:/media:rshared"
    ];
    extraOptions = [
      "--network=container:tailscale-decypharr"
      "--device=/dev/fuse:/dev/fuse:rwm"
      "--cap-add=SYS_ADMIN"
      "--security-opt=apparmor=unconfined"
    ];
  };
}
