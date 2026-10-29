{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.networkd;
in {
  options.homelab.networkd = {
    enable = mkEnableOption "ethernet networking via systemd-networkd";

    dhcp = mkOption {
      type = types.bool;
      default = false;
      description = "whether to obtain the network configuration via DHCP";
    };

    address = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "static ipv4 address, when DHCP is disabled";
      example = "10.0.5.20";
    };

    prefixLength = mkOption {
      type = types.ints.between 0 32;
      default = 16;
      description = "prefix len. defaults to 16";
    };

    gateway = mkOption {
      type = types.str;
      default = "10.0.0.1";
      description = "gateway. defaults to 10.0.0.1";
    };

    interface = mkOption {
      type = types.str;
      default = "en*";
      description = "interface match pattern. defaults to en*";
    };
  };

  config = mkIf cfg.enable {
    networking.useNetworkd = true;
    networking.networkmanager.enable = mkForce false;

    systemd.network.enable = true;

    systemd.network.networks."10-lan" = {
      matchConfig = {
        Name = cfg.interface;
        Type = "ether";
      };
      address = optional (!cfg.dhcp) "${cfg.address}/${toString cfg.prefixLength}";
      gateway = optional (!cfg.dhcp) cfg.gateway;
      networkConfig.DHCP = if cfg.dhcp then "yes" else "no";
      linkConfig.RequiredForOnline = "routable";
    };
  };
}