{config, ...}: let
  hostConfig = config;
in {
  containers.forgejo = {
    autoStart = true;
    macvlans = ["enp2s0"];
    enableTun = true;

    bindMounts."/run/secrets/headscale-preauthkey" = {
      hostPath = hostConfig.sops.secrets."headscale-preauthkey".path;
      isReadOnly = true;
    };

    config = {
      imports = [
        ../hardware/network.nix
      ];

      homelab.networkd = {
        enable = true;
        dhcp = true;
        interface = "mv-enp2s0";
        macAddress = "fa:03:bf:87:9d:e7";
      };
      networking.useHostResolvConf = false;
      networking.hostName = "forgejo";

      services.tailscale = {
        enable = true;
        authKeyFile = "/run/secrets/headscale-preauthkey";
        extraUpFlags = ["--login-server=https://headscale.endercass.me"];
        openFirewall = true;
      };

      services.forgejo = {
        enable = true;
        database.type = "sqlite3";
        stateDir = "/var/lib/forgejo";
        database.path = "/var/lib/forgejo/data/forgejo.db";
        settings = {
          server = {
            HTTP_PORT = 3000;
            ROOT_URL = "https://git.endercass.me/";
            SSH_DOMAIN = "git.endercass.me";
            SSH_PORT = 2222;
          };
          packages = {
            ENABLED = true;
          };
          oauth2_client = {
            ENABLE_AUTO_REGISTRATION = true;
          };
          service.DISABLE_REGISTRATION = true;
        };
      };

      environment.systemPackages = [config.services.forgejo.package];
      networking.firewall.allowedTCPPorts = [3000 2222];
      system.stateVersion = "26.05";
    };
  };
}
