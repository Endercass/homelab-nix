{
  lib,
  pkgs,
  config,
  ...
}: let
  serviceName = if (config.virtualisation.oci-containers.backend or "podman") == "podman" then "podman-wolf" else "docker-wolf";
  genWolfEnv = pkgs.writeShellScriptBin "gen-wolf-env" (
    lib.concatStringsSep "\n" [
      "set -euo pipefail"
      "IP=${pkgs.iproute2}/bin/ip"
      "AWK=${pkgs.gawk}/bin/awk"
      "CUT=${pkgs.coreutils}/bin/cut"
      "MKDIR=${pkgs.coreutils}/bin/mkdir"
      "DEV=\"$($IP route get 1.1.1.1 2>/dev/null | $AWK '/dev/ {for(i=1;i<=NF;i++){ if($i==\"dev\"){print $(i+1); exit}}}')\""
      "IPV4=\"\""
      "MAC=\"\""
      "if [ -n \"$DEV\" ]; then"
      "  IPV4=\"$($IP -4 -o addr show dev \"$DEV\" scope global 2>/dev/null | $AWK '{print $4}' | $CUT -d/ -f1 | head -n1)\""
      "  if [ -r /sys/class/net/\"$DEV\"/address ]; then IFS= read -r MAC < /sys/class/net/\"$DEV\"/address || true; fi"
      "fi"
      "$MKDIR -p /var/lib/wolf"
      "$MKDIR -p /var/lib/wolf/etc/cfg"
      "printf 'WOLF_INTERNAL_IP=%s\\n' \"$IPV4\" > /var/lib/wolf/wolf.env"
      "printf 'WOLF_INTERNAL_MAC=%s\\n' \"$MAC\" >> /var/lib/wolf/wolf.env"
      "if [ ! -s /var/lib/wolf/etc/cfg/config.toml ]; then"
      "  cat > /var/lib/wolf/etc/cfg/config.toml <<'EOF'"
      "[display]"
      "render-node = \"software\""
      "EOF"
      "fi"
    ]
  );
 in {
  virtualisation.oci-containers.containers.wolf = {
    image = "ghcr.io/games-on-whales/wolf:stable";

    # Run in host network mode so Moonlight can find it effortlessly
    extraOptions = [
      "--network=host"
      "--ipc=host"
      "--cap-add=NET_ADMIN"
      "--cap-add=NET_RAW"
      # Provide a docker-compatible socket path for Wolf's docker-probing code
      "-v=/run/podman/podman.sock:/var/run/docker.sock:ro"

      "--device=/dev/dri:/dev/dri"
      # "--device=/dev/kfd:/dev/kfd"
      "--device=/dev/uinput:/dev/uinput:rw"
      "--device=/dev/uhid:/dev/uhid:rw"

      "--security-opt=label=disable"
    ];

    # Persist wolf config
    volumes = [
      "/var/lib/wolf/etc:/etc/wolf"
      "/var/run/udev:/var/run/udev"
    ];

    environment = {
      # Force software rendering/Wayland for headless AMD BC250
      LIBGL_ALWAYS_SOFTWARE = "1";
      GALLIUM_DRIVER = "llvmpipe";
      MESA_LOADER_DRIVER_OVERRIDE = "llvmpipe";
      WLR_RENDERER = "pixman";
      WLR_BACKENDS = "headless";
      WAYLAND_DISPLAY = "wayland-0";
      XDG_RUNTIME_DIR = "/run/user/wolf";
    };

    # Supply dynamic env at start (host path)
    environmentFiles = [ "/var/lib/wolf/wolf.env" ];
  };

  # Generate the env file before starting the container (runs on target at service start)
  systemd.services.${serviceName} = {
    preStart = "${genWolfEnv}/bin/gen-wolf-env";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # Make sure directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/wolf 0755 root root -"
    "d /var/lib/wolf/etc 0755 root root -"
  ];

  # Open the required Moonlight streaming firewall ports if you disable host mode later
  networking.firewall.allowedTCPPorts = [ 47984 47989 48010 ];
  networking.firewall.allowedUDPPorts = [ 47999 48010 48100 48200 5353 ];
}