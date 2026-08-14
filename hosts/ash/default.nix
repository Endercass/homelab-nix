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
    address = "10.0.9.1";
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

  containers.authentik = {
    autoStart = true;
    macvlans = ["enp2s0"];

    bindMounts."/run/secrets/authentik-env" = {
      hostPath = config.sops.secrets."authentik-env".path;
      isReadOnly = true;
    };

    bindMounts."/run/secrets/authentik-ldap-env" = {
      hostPath = config.sops.secrets."authentik-ldap-env".path;
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
        address = "10.0.9.2";
        interface = "mv-enp2s0";
      };
      networking.nameservers = ["10.0.0.1"];
      networking.useHostResolvConf = false;
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