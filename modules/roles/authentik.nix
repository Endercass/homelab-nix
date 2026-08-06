{...}: {
  services.authentik = {
    enable = true;
    # Bind-mounted into the container from the host's sops-nix secret store
    # (see containers.authentik.bindMounts in hosts/ash/default.nix).
    environmentFile = "/run/secrets/authentik-env";
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };

  networking.firewall.allowedTCPPorts = [9000];

  system.stateVersion = "26.05";
}
