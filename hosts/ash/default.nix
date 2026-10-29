{
  config,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/core
    ../../modules/hardware/luks-usb-key.nix
    ../../modules/hardware/lvm-initrd.nix
    ../../modules/hardware/network.nix
    ../../modules/roles/ssh.nix
    ../../modules/roles/discord-role-bot.nix
  ];

  networking.hostName = "ash";

  users.users.root.openssh.authorizedKeys.keys = with config.homelab.pubkeys; [
    master
  ];

  homelab.networkd = {
    enable = true;
    dhcp = true;
  };

  homelab.luksUsbKey.enable = true;

  sops.secrets."authentik-env" = {
    sopsFile = ../../secrets/ash/authentik.env;
    format = "dotenv";
    key = "";
    mode = "0444";
  };

  sops.secrets."authentik-ldap-env" = {
    sopsFile = ../../secrets/ash/authentik-ldap.env;
    format = "dotenv";
    key = "";
    mode = "0444";
  };

  sops.secrets."headscale-preauthkey" = {
    sopsFile = ../../secrets/ash/headscale-preauthkey;
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

  containers.authentik = {
    autoStart = true;
    macvlans = ["enp2s0"];
    enableTun = true; # grants CAP_NET_ADMIN + /dev/net/tun for tailscale

    bindMounts."/run/secrets/authentik-env" = {
      hostPath = config.sops.secrets."authentik-env".path;
      isReadOnly = true;
    };

    bindMounts."/run/secrets/authentik-ldap-env" = {
      hostPath = config.sops.secrets."authentik-ldap-env".path;
      isReadOnly = true;
    };

    bindMounts."/run/secrets/headscale-preauthkey" = {
      hostPath = config.sops.secrets."headscale-preauthkey".path;
      isReadOnly = true;
    };

    config = {
      imports = [
        inputs.authentik-nix.nixosModules.default
        ../../modules/hardware/network.nix
        ../../modules/roles/authentik.nix
      ];

      homelab.networkd = {
        enable = true;
        dhcp = true;
        interface = "mv-enp2s0";
      };
      networking.nameservers = ["10.0.0.1"];
      networking.useHostResolvConf = false;

      services.tailscale = {
        enable = true;
        authKeyFile = "/run/secrets/headscale-preauthkey";
        extraUpFlags = ["--login-server=https://headscale.endercass.me"];
        openFirewall = true;
      };
    };
  };

  boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-label/NIXOS-LUKS";

  fileSystems."/" = {
    device = "/dev/NIXOS_LVM/ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS-BOOT";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  swapDevices = [
    {device = "/dev/NIXOS_LVM/SWAP";}
  ];

  system.stateVersion = "26.05";
}