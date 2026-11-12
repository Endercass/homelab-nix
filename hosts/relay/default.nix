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
      hash = "sha256-6E+9btb7joeE1k2UNnC1Avo3soyCT2PmiOHNbN2lvYk=";
      doInstallCheck = false;
    };

    globalConfig = ''
      servers {
        trusted_proxies static private_ranges
      }
    '';

    extraConfig = ''
      (proxy_headers) {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
      }
    '';

    virtualHosts = {
      ":9999".extraConfig = ''
        respond "You have either tried to reach a page that doesn't exist, are checking the status intentionally, or the server is down. Ping @endercass on discord if there is no additional information provided below"
      '';
      "relay.endercass.me".extraConfig = ''
        respond "To be done: set up relay server."
      '';


      "https://auth.endercass.me".extraConfig = ''
        reverse_proxy http://authentik:9000 http://localhost:9999 {
          import proxy_headers
          lb_policy first
          lb_try_duration 1s
          fail_duration 30s
          transport http {
            dial_timeout 500ms
          }
        }
      '';

      "https://jelly.endercass.me".extraConfig = ''
        reverse_proxy http://ash:8096 http://localhost:9999 {
          import proxy_headers
          lb_policy first
          lb_try_duration 1s
          fail_duration 30s
          transport http {
            dial_timeout 500ms
          }
        }
      '';

      "https://seerr.endercass.me".extraConfig = ''
        reverse_proxy http://ash:5055 http://localhost:9999 {
          import proxy_headers
          lb_policy first
          lb_try_duration 1s
          fail_duration 30s
          transport http {
            dial_timeout 500ms
          }
        }
      '';

      "https://headscale.endercass.me".extraConfig = ''
        reverse_proxy http://127.0.0.1:8080 http://localhost:9999 {
          import proxy_headers
          lb_policy first
          lb_try_duration 1s
          fail_duration 30s
          transport http {
            dial_timeout 500ms
          }
        }
      '';
    };


  };

  networking.firewall.allowedTCPPorts = [80 443 8443 9999 8005 5222 5269 25565 25567 6767 2022 2023 22];
  networking.firewall.allowedUDPPorts = [3478 24454 5520 19132 16261 16262];
  networking.firewall.trustedInterfaces = ["tailscale0"];

  sops.secrets."headscale-oidc-client-secret" = {
    sopsFile = ../../secrets/relay/headscale-oidc-client-secret;
    format = "binary";
    key = "";
    mode = "0444";
  };

  services.headscale = {
    enable = true;
    package = pkgs.headscale.overrideAttrs (old: {
      version = "${old.version}-pr3473";
      src = pkgs.fetchFromGitHub {
        owner = "juanfont";
        repo = "headscale";
        rev = "f2aaf74e01d9d901f154032cdf237b4ef40021a5";
        hash = "sha256-vR3kEvM/5Y23uhCTuhaiKUjKx0uNW5cszrp87W8sfiM=";
      };
      postPatch = ''
        substituteInPlace hscontrol/types/version.go \
          --replace-fail 'Version:   "dev"' 'Version:   "${old.version}-pr3473"' \
          --replace-fail 'Commit:    "unknown"' 'Commit:    "f2aaf74e01d9d901f154032cdf237b4ef40021a5"'
      '';
      vendorHash = "sha256-9CaB0iKGP3PpdG1bKomOAWwRXASnZhyMYaLh82hrYdk=";
    });
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://headscale.endercass.me";
      dns = {
        magic_dns = true;
        base_domain = "home.endercass.me";
        override_local_dns = false;
        nameservers.global = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
      oidc = {
        issuer = "https://auth.endercass.me/application/o/headscale/";
        client_id = "uBvG61XPTsZh80XVoceoucybiVGdgU30YeF1Kcqv";
        client_secret_path = config.sops.secrets."headscale-oidc-client-secret".path;
        only_start_if_oidc_is_available = false;
        retry_interval = "30s";
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
    extraUpFlags = ["--login-server=https://headscale.endercass.me" "--advertise-exit-node"];
    useRoutingFeatures = "server";
    openFirewall = true;
  };

  systemd.services.tailscale-advertise-exit-node = {
    description = "Advertise relay as a Tailscale exit node";
    wantedBy = ["multi-user.target"];
    wants = ["tailscaled-autoconnect.service"];
    after = ["tailscaled-autoconnect.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${pkgs.tailscale}/bin/tailscale set --advertise-exit-node";
  };

  system.stateVersion = "26.05";
}
