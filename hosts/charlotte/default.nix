{
  config,
  lib,
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
    ../../modules/roles/podman.nix
    ../../modules/roles/wolf.nix
  ];

  hardware.bc250 = {
    enable = true;

    features = {
      aic8800d80.enable = false;
      cuLiveManager.enable = true;
      cpuOverclock.enable = false;
      vramSplit = null; # example: 512

      vramDynamicSplit = null; # example: 4096

      sensors.enable = true; 
      gpuGovernor.enable = true;
      zswap.enable = true;
    };
  };

  networking.hostName = "charlotte";

  users.users.root.openssh.authorizedKeys.keys = with config.homelab.pubkeys; [
    master
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    KERNEL=="uhid", GROUP="input", MODE="0660", OPTIONS+="static_node=uhid"
  '';

  virtualisation.oci-containers.backend = "podman";



  homelab.networkd = {
    enable = true;
    dhcp = true;
  };

  homelab.luksUsbKey.enable = true;

  sops.secrets."headscale-preauthkey" = {
    sopsFile = ../../secrets/charlotte/headscale-preauthkey;
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