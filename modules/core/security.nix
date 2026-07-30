{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.homelab.pubkeys = mkOption {
    type = types.attrsOf types.str;
    default = {};
    description = "Named SSH public keys usable across hosts.";
    example = {
      master = "ssh-ed25519 AAAA...";
    };
  };

  config.homelab.pubkeys = {
    master = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPjKbQaiiQ+kXkbRnqtFKZGOau4qmkEmBk4gcb46w3ys";
  };
}