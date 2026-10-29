# look for a labeled USB key in the initrd and copy the key file to /run/cryptsetup-keys.d/<luksName>.key
# this allows the server to be unlocked by someone near the server with a USB key, without having to type a password on the server itself
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.luksUsbKey;

  findUsbKeyScript = pkgs.writeShellScript "find-usb-key" ''
    set -eu
    DEV="/dev/$1"
    echo "find-usb-key: checking $DEV"

    udevadm settle --timeout=5 || true

    LABEL=$(blkid -s LABEL -o value "$DEV" 2>&1) || {
      echo "find-usb-key: blkid failed on $DEV: $LABEL"
      exit 0
    }
    echo "find-usb-key: $DEV has label '$LABEL'"

    if [ "$LABEL" != "${cfg.usbLabel}" ]; then
      echo "find-usb-key: $DEV label does not match, skipping"
      exit 0
    fi

    MNT=$(mktemp -d)
    if ! mount -o ro "$DEV" "$MNT" 2>&1; then
      echo "find-usb-key: failed to mount $DEV"
      rmdir "$MNT"
      exit 0
    fi
    echo "find-usb-key: mounted $DEV at $MNT"
    ls -la "$MNT" || true

    if [ -f "$MNT/${cfg.keyFileName}" ]; then
      echo "find-usb-key: found ${cfg.keyFileName}, copying"
      mkdir -p /run/cryptsetup-keys.d
      cp "$MNT/${cfg.keyFileName}" /run/cryptsetup-keys.d/${cfg.luksName}.key
      chmod 000 /run/cryptsetup-keys.d/${cfg.luksName}.key
      echo "find-usb-key: restarting cryptsetup unit"
      systemctl restart systemd-cryptsetup@${cfg.luksName}.service || echo "find-usb-key: restart failed"
    else
      echo "find-usb-key: ${cfg.keyFileName} not found on $DEV"
    fi

    umount "$MNT"
    rmdir "$MNT"
  '';
in {
  options.homelab.luksUsbKey = {
    enable = mkEnableOption "unlocking a LUKS device from a labeled USB key in the initrd";

    usbLabel = mkOption {
      type = types.str;
      default = "HOMELAB-KEYS";
      description = "Filesystem LABEL of the USB stick carrying key files.";
    };

    keyFileName = mkOption {
      type = types.str;
      default = "${config.networking.hostName}.key";
      defaultText = literalExpression ''"''${config.networking.hostName}.key"'';
      description = "Name of the key file to look for on the USB stick, for this host.";
    };

    luksName = mkOption {
      type = types.str;
      default = "cryptroot";
      description = ''
        Name of the LUKS device, i.e. the attribute name under
        boot.initrd.luks.devices.<name>.
      '';
    };
  };

  config = mkIf cfg.enable {
    # boot.initrd.systemd.enable = true;
    boot.initrd.systemd.initrdBin = with pkgs; [util-linux coreutils];
    boot.initrd.systemd.storePaths = [findUsbKeyScript];

    boot.initrd.systemd.services."find-usb-key@" = {
      description = "Copy LUKS key from %I if labeled ${cfg.usbLabel}";
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${findUsbKeyScript} %I";
      };
    };

    boot.initrd.services.udev.rules = ''
      SUBSYSTEM=="block", ACTION=="add", ENV{DEVTYPE}=="partition", TAG+="systemd", ENV{SYSTEMD_WANTS}+="find-usb-key@%k.service"
    '';

    boot.initrd.luks.devices.${cfg.luksName} = {
      keyFile = mkDefault "/run/cryptsetup-keys.d/${cfg.luksName}.key";
      keyFileTimeout = mkDefault 10;
    };
  };
}
