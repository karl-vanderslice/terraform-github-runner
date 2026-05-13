{
  pkgs,
  lib,
  ...
}: {
  system.stateVersion = "24.11";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["vault"];

  services.cloud-init.enable = false;

  users.groups.actions = {};
  users.groups.atticd = {};
  users.groups.caddy = {};

  users.users.actions = {
    isNormalUser = true;
    description = "GitHub Actions runner user";
    group = "actions";
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
    createHome = true;
  };

  users.users.caddy = {
    isSystemUser = true;
    group = "caddy";
    description = "Caddy reverse proxy user";
    home = "/var/lib/caddy";
    createHome = true;
  };

  security.sudo.wheelNeedsPassword = false;

  virtualisation.docker.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/atticd 0750 atticd atticd -"
    "d /var/lib/caddy 0750 caddy caddy -"
    "d /var/lib/caddy/.config 0750 caddy caddy -"
    "d /var/lib/caddy/.local 0750 caddy caddy -"
    "d /var/lib/caddy/.local/share 0750 caddy caddy -"
    "d /var/lib/github-runner-bootstrap 0750 root root -"
  ];

  environment.systemPackages = with pkgs; [
    attic-client
    attic-server
    caddy
    curl
    git
    github-runner
    jq
    nftables
    unzip
    bash
    vault
  ];

  systemd.services.github-runner-metadata-bootstrap = {
    description = "Run Hetzner metadata bootstrap";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      user_data=/run/hetzner-user-data
      bootstrap_script=/usr/local/bin/github-runner-bootstrap

      install -d -m 0755 /usr/local/bin

      ${pkgs.curl}/bin/curl -fsSL http://169.254.169.254/latest/user-data -o "$user_data"

      ${pkgs.gawk}/bin/awk '
        /^      #!/ { capture = 1 }
        capture && /^runcmd:/ { exit }
        capture {
          sub(/^      /, "")
          print
        }
      ' "$user_data" > "$bootstrap_script"

      if [[ ! -s "$bootstrap_script" ]]; then
        echo "failed to extract bootstrap script from Hetzner user-data" >&2
        exit 1
      fi

      chmod 0755 "$bootstrap_script"
      ${pkgs.bash}/bin/bash "$bootstrap_script"
    '';
  };

  systemd.services.atticd = {
    description = "Attic binary cache server";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
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

  systemd.services.attic-caddy = {
    description = "Caddy reverse proxy for Attic";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target" "atticd.service"];
    after = ["network-online.target" "atticd.service"];
    unitConfig.ConditionPathExists = "/etc/caddy/Caddyfile";
    serviceConfig = {
      Type = "simple";
      User = "caddy";
      Group = "caddy";
      WorkingDirectory = "/var/lib/caddy";
      Environment = [
        "XDG_CONFIG_HOME=/var/lib/caddy/.config"
        "XDG_DATA_HOME=/var/lib/caddy/.local/share"
      ];
      AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
      ExecStart = "${pkgs.caddy}/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile";
      ExecReload = "${pkgs.caddy}/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };
}
