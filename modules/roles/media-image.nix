args:
{
  lib,
  pkgs,
  ...
}:
let
  imagePath = args.imagePath or "/var/lib/media-disk.img";
  imageSize = args.imageSize or "64G";
  mountPoint = args.mountPoint or "/media";
  label = args.label or "MEDIA";
  subdirs =
    args.subdirs or [
      "jellyfin/movies"
      "jellyfin/tv"
      "jellyfin/music"
      "downloads"
      "transcode"
    ];
  mountOptions =
    (args.mountOptions or [
      "compress=zstd"
      "noatime"
    ]
    )
    ++ [ "loop" ];

  subdirPaths = map (d: mountPoint + "/" + d) subdirs;

  postMountScript = pkgs.writeShellScript "media-post-mount-setup" ''
    set -euo pipefail
    mp=${lib.escapeShellArg mountPoint}
    if ! ${pkgs.util-linux}/bin/mountpoint -q "$mp"; then
      echo "$mp is not mounted; exiting"
      exit 1
    fi
    ${lib.concatStringsSep "\n" (
      map (p: ''
        mkdir -p ${lib.escapeShellArg p}
      '') subdirPaths
    )}
  '';

  setupScript = pkgs.writeShellScript "media-image-setup" ''
    set -euo pipefail
    img=${lib.escapeShellArg imagePath}
    size=${lib.escapeShellArg imageSize}
    label=${lib.escapeShellArg label}
    mp=${lib.escapeShellArg mountPoint}

    mkdir -p "$(dirname "$img")"

    if [ ! -f "$img" ]; then
      echo "Creating sparse image $img of size $size"
      if ! ${pkgs.util-linux}/bin/fallocate -l "$size" "$img"; then
        echo "fallocate failed, falling back to truncate"
        ${pkgs.coreutils}/bin/truncate -s "$size" "$img"
      fi
      echo "Formatting $img as Btrfs with label $label"
      ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f -L "$label" "$img"
    fi

    mkdir -p "$mp"
    chown root:root "$img"
    chmod 0640 "$img"
  '';
in
{
  # Create the image (if missing) during activation, before systemd restarts
  system.activationScripts.mediaImageSetup = {
    deps = [ ];
    text = ''
      ${setupScript}
    '';
  };

  fileSystems.${mountPoint} = {
    device = imagePath;
    fsType = "btrfs";
    options = mountOptions;
    neededForBoot = false;
  };

  systemd.services.media-post-mount-setup = {
    description = "Create media directory structure after mount";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = postMountScript;
      RequiresMountsFor = [ mountPoint ];
    };
    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];
  };
}
