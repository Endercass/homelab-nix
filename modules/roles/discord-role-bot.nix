{config, ...}: {
  users.groups.discord-role-bot-secrets = {};

  sops.secrets."discord-role-bot-config" = {
    sopsFile = ../../secrets/ash/discord-role-bot-config.json;
    format = "json";
    key = "";
    group = "discord-role-bot-secrets";
    mode = "0440";
  };

  systemd.services.discord-role-bot.serviceConfig.SupplementaryGroups = ["discord-role-bot-secrets"];

  services.discord-role-bot = {
    enable = true;
    configFile = config.sops.secrets."discord-role-bot-config".path;
  };
}
