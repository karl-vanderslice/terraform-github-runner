{
  pkgs,
  lib,
  ...
}: {
  system.stateVersion = "24.11";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["vault"];

  services.cloud-init.enable = true;

  users.groups.atticd = {};

  users.users.actions = {
    isNormalUser = true;
    description = "GitHub Actions runner user";
    extraGroups = ["wheel" "docker"];
    home = "/opt/actions-runner";
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
    description = "Attic server user";
    home = "/var/lib/atticd";
    createHome = false;
  };

  security.sudo.wheelNeedsPassword = false;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    attic-client
    attic-server
    curl
    git
    jq
    unzip
    bash
    vault
  ];

  systemd.services.atticd = {
    description = "Attic binary cache server";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target" "cloud-final.service"];
    after = ["network-online.target" "cloud-final.service"];
    unitConfig.ConditionPathExists = "/etc/atticd.toml";
    serviceConfig = {
      Type = "simple";
      User = "atticd";
      Group = "atticd";
      Restart = "on-failure";
      RestartSec = 5;
      EnvironmentFile = "-/etc/atticd.env";
      ExecStart = "${pkgs.attic-server}/bin/atticd --mode monolithic -f /etc/atticd.toml";
      WorkingDirectory = "/var/lib/atticd";
    };
  };

  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };
}
