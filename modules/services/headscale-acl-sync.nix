{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.headscale-acl-sync;
  configFile = pkgs.writeText "headscale-acl-sync.json" (
    builtins.toJSON {
      authentik_url = cfg.authentikUrl;
      group_uuid = cfg.groupUuid;
      oidc_issuer = cfg.oidcIssuer;
      headscale_socket = cfg.headscaleSocket;
      static_policy = cfg.staticPolicyFile;
      policy_path = cfg.policyPath;
      headscale_pid_command = [
        "${pkgs.systemd}/bin/systemctl"
        "show"
        "-p"
        "MainPID"
        "--value"
        "headscale.service"
      ];
      validation_command = [
        "${config.services.headscale.package}/bin/headscale"
        "policy"
        "check"
        "--file"
      ];
    }
  );
  script = pkgs.writeText "headscale-acl-sync.py" (builtins.readFile ./headscale-acl-sync.py);
in
{
  options.services.headscale-acl-sync = {
    enable = lib.mkEnableOption "Authentik to Headscale ACL synchronization";
    authentikUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.endercass.me";
    };
    groupUuid = lib.mkOption {
      type = lib.types.str;
      default = "c56c533f-feeb-4697-9860-86583c3813aa";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.endercass.me/application/o/headscale/";
    };
    tokenFile = lib.mkOption {
      type = lib.types.path;
    };
    headscaleSocket = lib.mkOption {
      type = lib.types.path;
      default = "/var/run/headscale/headscale.sock";
    };
    policyPath = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/headscale-acl-sync/policy.hujson";
    };
    staticPolicyFile = lib.mkOption {
      type = lib.types.path;
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.headscale-acl-sync = { };
    users.users.headscale-acl-sync = {
      isSystemUser = true;
      group = "headscale";
    };

    systemd.services.headscale-acl-sync = {
      description = "Synchronize Authentik administrators to Headscale ACLs";
      after = [
        "headscale.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "headscale-acl-sync";
        Group = "headscale";
        ExecStart = "${pkgs.python3}/bin/python ${script}";
        Environment = [
          "HEADSCALE_ACL_SYNC_CONFIG=${configFile}"
          "AUTHENTIK_TOKEN_FILE=${cfg.tokenFile}"
        ];
        StateDirectory = "headscale-acl-sync";
        UMask = "0027";
        NoNewPrivileges = true;
        AmbientCapabilities = [ "CAP_KILL" ];
        CapabilityBoundingSet = [ "CAP_KILL" ];
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/headscale-acl-sync" ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    system.activationScripts.headscale-acl-sync-policy.text = ''
      install -d -m 0750 -o headscale-acl-sync -g headscale ${lib.escapeShellArg (builtins.dirOf cfg.policyPath)}
      if [ ! -e ${lib.escapeShellArg cfg.policyPath} ]; then
        install -D -m 0640 ${lib.escapeShellArg cfg.staticPolicyFile} ${lib.escapeShellArg cfg.policyPath}
        chown headscale-acl-sync:headscale ${lib.escapeShellArg cfg.policyPath}
      else
        chown headscale-acl-sync:headscale ${lib.escapeShellArg cfg.policyPath}
        chmod 0640 ${lib.escapeShellArg cfg.policyPath}
      fi
    '';

    systemd.timers.headscale-acl-sync = {
      description = "Synchronize Authentik administrators to Headscale ACLs every five minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
        Unit = "headscale-acl-sync.service";
      };
    };
  };
}
