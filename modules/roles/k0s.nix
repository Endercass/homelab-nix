{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.homelab.k0s;
  workerArgs =
    (lib.optional (cfg.workerProfile != null) "--profile=${lib.escapeShellArg cfg.workerProfile}")
    ++ (lib.optional (
      cfg.nodeLabels != [ ]
    ) "--labels=${lib.escapeShellArg (lib.concatStringsSep "," cfg.nodeLabels)}")
    ++ (lib.optional (
      cfg.nodeTaints != [ ]
    ) "--taints=${lib.escapeShellArg (lib.concatStringsSep "," cfg.nodeTaints)}")
    ++ cfg.extraArgs;
  kubeletArgs = lib.optional (cfg.nodeIp != null) "--kubelet-extra-args=--node-ip=${cfg.nodeIp}";
in
{
  imports = [ inputs.k0s-nix.nixosModules.default ];

  options.homelab.k0s = {
    enable = lib.mkEnableOption "the k0s Kubernetes node";

    role = lib.mkOption {
      type = lib.types.enum [
        "controller"
        "controller+worker"
        "worker"
        "single"
      ];
      default = "worker";
      description = "The k0s role for this node.";
    };

    apiAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The local address used by the k0s API server.";
    };

    nodeIp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The address kubelet advertises as the node InternalIP.";
    };

    externalApiAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The address controllers and workers use to reach the k0s API.";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = "The k0s cluster name.";
    };

    isLeader = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this controller bootstraps the k0s cluster.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/k0s/k0stoken";
      description = "Path to the k0s join token.";
    };

    nodeLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Labels applied when a worker first joins the cluster.";
    };

    nodeTaints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Taints applied when a worker first joins the cluster.";
    };

    workerProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional k0s worker profile.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed to k0s.";
    };

    spec = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional services.k0s.spec settings.";
    };
  };

  config = lib.mkMerge [
    { nixpkgs.overlays = [ inputs.k0s-nix.overlays.default ]; }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.apiAddress != null;
          message = "homelab.k0s.apiAddress must be set when k0s is enabled.";
        }
        {
          assertion = cfg.role == "worker" || cfg.isLeader || cfg.externalApiAddress != "";
          message = "homelab.k0s.externalApiAddress must be set for non-leader controllers.";
        }
        {
          assertion = !cfg.isLeader || cfg.role != "worker";
          message = "homelab.k0s.isLeader cannot be enabled for a worker.";
        }
      ];

      environment.systemPackages = [
        config.services.k0s.package
      ];

      systemd.services.k0s = {
        after = [ "tailscaled-autoconnect.service" ];
        wants = [ "tailscaled-autoconnect.service" ];
      };

      networking.firewall.allowedTCPPorts =
        lib.optionals (cfg.role != "worker") [
          6443
          8133
          9443
        ]
        ++ lib.optionals (cfg.role == "worker") [
          10250
          8132
        ];

      services.k0s = {
        enable = true;
        role = cfg.role;
        clusterName = cfg.clusterName;
        tokenFile = cfg.tokenFile;
        controller.isLeader = cfg.isLeader;
        extraArgs = lib.concatStringsSep " " (
          kubeletArgs ++ (if cfg.role == "worker" then workerArgs else cfg.extraArgs)
        );
        spec = lib.recursiveUpdate cfg.spec {
          api = {
            address = cfg.apiAddress;
            externalAddress = cfg.externalApiAddress;
          };
        };
      };
    })
  ];
}
