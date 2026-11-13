{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core
    ../../modules/hardware/luks-usb-key.nix
    ../../modules/hardware/lvm-initrd.nix
    ../../modules/hardware/network.nix
    ../../modules/roles/ssh.nix
  ];

  networking.hostName = "eiji";

  users.users.root.openssh.authorizedKeys.keys = with config.homelab.pubkeys; [
    master
  ];

  homelab.networkd = {
    enable = true;
    dhcp = true;
  };

  homelab.luksUsbKey.enable = true;

  sops.secrets."headscale-preauthkey" = {
    sopsFile = ../../secrets/eiji/headscale-preauthkey;
    format = "binary";
    key = "";
    mode = "0400";
  };

  sops.secrets."k0s-token" = {
    sopsFile = ../../secrets/eiji/k0s-token;
    format = "binary";
    key = "";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."headscale-preauthkey".path;
    extraUpFlags = [ "--login-server=https://headscale.endercass.me" ];
    openFirewall = true;
  };

  homelab.k0s = {
    enable = true;
    role = "worker";
    apiAddress = "100.81.0.4";
    nodeIp = "100.81.0.4";
    tokenFile = config.sops.secrets."k0s-token".path;
    nodeLabels = [ "node-pool=infrastructure" ];
  };

  boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-label/NIXOS-LUKS";

  fileSystems."/" = {
    device = "/dev/NIXOS_LVM/ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS-BOOT";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [
    { device = "/dev/NIXOS_LVM/SWAP"; }
  ];

  system.stateVersion = "26.05";
}
