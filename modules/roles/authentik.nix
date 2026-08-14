{...}: {
  services.authentik = {
    enable = true;
    environmentFile = "/run/secrets/authentik-env";
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
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
