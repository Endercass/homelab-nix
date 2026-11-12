{...}: {
  services.authentik = {
    enable = true;
    environmentFile = "/run/secrets/authentik-env";
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
      listen.trusted_proxy_cidrs = [
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "fe80::/10"
        "::1/128"
        "fd7a:115c:a1e0::/48"
      ];
    };
  };

  services.authentik-ldap = {
    enable = true;
    environmentFile = "/run/secrets/authentik-ldap-env";
  };
  systemd.services.authentik-ldap.serviceConfig.AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];

  networking.firewall.allowedTCPPorts = [9000 389 636];

  system.stateVersion = "26.05";
}
