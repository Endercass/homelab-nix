{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/core
     ../../modules/hardware/network.nix
    ../../modules/roles/ssh.nix
  ];

  networking.hostName = "relay";
  networking.domain = "endercass.me";

  homelab.networkd = {
    enable = true;
    address = "66.23.198.202";
    prefixLength = 24;
    gateway = "66.23.198.1";
  };

  users.users.root.openssh.authorizedKeys.keys = with config.homelab.pubkeys; [
    master
  ];

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = ["github.com/mholt/caddy-l4@master"];
      hash = "sha256-UIv8PxtJMlX7qClnPazFsSSl7G1BzsTT8VjrMIfB46Q=";
      doInstallCheck = false;
    };

    virtualHosts = {
      ":9999".extraConfig = ''
        respond "You have either tried to reach a page that doesn't exist, are checking the status intentionally, or the server is down. Ping @endercass on discord if there is no additional information provided below"
      '';
      "relay.endercass.me".extraConfig = ''
        respond "To be done: set up relay server."
      '';

      "https://auth.endercass.me".extraConfig = ''
        reverse_proxy http://authentik:9000 http://localhost:9999 {
          lb_policy first
          lb_try_duration 1s
          fail_duration 30s
          transport http {
            dial_timeout 500ms
          }
        }
      '';

      "https://headscale.endercass.me".extraConfig = ''
        reverse_proxy http://127.0.0.1:8080
      '';
    };


  };

  networking.firewall.allowedTCPPorts = [80 443 8443 9999 8005 5222 5269 25565 25567 6767 2022 2023 22];
  networking.firewall.allowedUDPPorts = [3478 24454 5520 19132 16261 16262];

  sops.secrets."headscale-oidc-client-secret" = {
    sopsFile = ../../secrets/relay/headscale-oidc-client-secret;
    format = "binary";
    key = "";
    mode = "0444";
  };

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://headscale.endercass.me";
      dns = {
        magic_dns = true;
        base_domain = "home.endercass.me";
        override_local_dns = false;
      };
      oidc = {
        issuer = "https://auth.endercass.me/application/o/headscale/";
        client_id = "uBvG61XPTsZh80XVoceoucybiVGdgU30YeF1Kcqv";
        client_secret_path = config.sops.secrets."headscale-oidc-client-secret".path;
      };
    };
  };

  sops.secrets."headscale-preauthkey" = {
    sopsFile = ../../secrets/relay/headscale-preauthkey;
    format = "binary";
    key = "";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."headscale-preauthkey".path;
    extraUpFlags = ["--login-server=https://headscale.endercass.me"];
    openFirewall = true;
  };

  system.stateVersion = "26.05";
}
