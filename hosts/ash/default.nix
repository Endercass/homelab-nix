{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/core
    ../../modules/hardware/luks-usb-key.nix
    ../../modules/hardware/lvm-initrd.nix
    ../../modules/hardware/network.nix
    ../../modules/roles/ssh.nix
    ../../modules/roles/docker.nix
    ../../modules/roles/radarr.nix
    ../../modules/roles/sonarr.nix
    ../../modules/roles/prowlarr.nix
    ../../modules/roles/seerr.nix
    ../../modules/roles/decypharr.nix
    ../../modules/roles/authentik.nix
    ../../modules/roles/forgejo.nix
    inputs.nixos-jellyfin.nixosModules.default
    ../../modules/roles/discord-role-bot.nix
    (import ../../modules/roles/media-image.nix {
      imagePath = "/var/lib/media-disk.img";
      imageSize = "64G";
      mountPoint = "/media";
      label = "MEDIA";
      subdirs = [
        "movies"
        "music"
        "tv"
        "downloads"
        "downloads/radarr"
        "downloads/sonarr"
        "downloads/lidarr"
      ];
    })
  ];

  networking.hostName = "ash";

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    cacheDir = "/media/transcode";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver   
      libvpl              
      libva-utils         
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-vaapi-driver
    ];
  };

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

  homelab.k0s = {
    enable = true;
    role = "controller+worker";
    isLeader = true;
    apiAddress = "100.81.0.3";
    nodeIp = "100.81.0.3";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."headscale-preauthkey".path;
    extraUpFlags = ["--login-server=https://headscale.endercass.me"];
    openFirewall = true;
  };

  environment.etc."fuse.conf".text = ''
    user_allow_other
  '';

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