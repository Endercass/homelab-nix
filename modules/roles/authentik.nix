{config, inputs, ...}: let
  hostConfig = config;
in {
  containers.authentik = {
    autoStart = true;
    macvlans = ["enp2s0"];
    enableTun = true;

    bindMounts."/run/secrets/authentik-env" = {
      hostPath = hostConfig.sops.secrets."authentik-env".path;
      isReadOnly = true;
    };

    bindMounts."/run/secrets/authentik-ldap-env" = {
      hostPath = hostConfig.sops.secrets."authentik-ldap-env".path;
      isReadOnly = true;
    };

    bindMounts."/run/secrets/headscale-preauthkey" = {
      hostPath = hostConfig.sops.secrets."headscale-preauthkey".path;
      isReadOnly = true;
    };

    config = {
      imports = [
        inputs.authentik-nix.nixosModules.default
        ../hardware/network.nix
      ];

      homelab.networkd = {
        enable = true;
        dhcp = true;
        interface = "mv-enp2s0";
        macAddress = "8a:70:5e:23:f5:48";
      };
      networking.useHostResolvConf = false;

      services.tailscale = {
        enable = true;
        authKeyFile = "/run/secrets/headscale-preauthkey";
        extraUpFlags = ["--login-server=https://headscale.endercass.me"];
        openFirewall = true;
      };

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
    };
  };
}
