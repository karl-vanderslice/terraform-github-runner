{
  config,
  lib,
  pkgs,
  ...
}: let
  generated = builtins.fromJSON (builtins.readFile ./generated-config.json);

  stateDir = "/var/lib/terraform-github-runner";
  runnerGroup = "github-runner";
  runnerUser = "github-runner";
  atticUser = "atticd";
  runnerTokenFile = "${stateDir}/github-runner-token";
  atticClientTokenFile = "${stateDir}/attic-client-token";
  atticEnvironmentFile = "${stateDir}/atticd.env";
  atticPublicKeyFile = "${stateDir}/attic-public-key";
  tunnelCredentialsFile = "${stateDir}/cloudflare-tunnel-attic.json";
  atticLocalEndpoint = "http://127.0.0.1:${toString generated.attic.localPort}/";
  atticRemoteName = "bootstrap-local";
  atticCacheScope = "${atticRemoteName}:${generated.attic.cacheName}";
  tunnelUnit = "cloudflared-tunnel-${generated.cloudflareTunnel.id}";
  atticadmBin = "${config.services.atticd.package}/bin/atticadm";
in {
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "usb_storage"
    "usbhid"
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;

  fileSystems."/boot".neededForBoot = true;

  networking.firewall = {
    allowedTCPPorts = [22];
    enable = true;
  };
  networking.hostName = generated.runner.name;
  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    networks."10-uplink" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  services.resolved.enable = true;

  time.timeZone = "UTC";

  users.users.root.openssh.authorizedKeys.keys = generated.ssh.authorizedKeys;
  users = {
    groups = {
      "${atticUser}" = {};
      "${runnerGroup}" = {};
    };
    users = {
      "${atticUser}" = {
        createHome = true;
        group = atticUser;
        home = "/var/lib/atticd";
        isSystemUser = true;
      };
      "${runnerUser}" = {
        createHome = true;
        group = runnerGroup;
        home = "/var/lib/github-runner";
        isSystemUser = true;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root ${runnerGroup} - -"
    "d /var/lib/github-runner 0750 ${runnerUser} ${runnerGroup} - -"
    "d /var/lib/github-runner/work 0750 ${runnerUser} ${runnerGroup} - -"
  ];

  environment.systemPackages = with pkgs; [
    attic-client
    curl
    git
    jq
  ];

  services.atticd = {
    enable = true;
    environmentFile = atticEnvironmentFile;
    settings = {
      api-endpoint = "${generated.attic.publicEndpoint}/";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      listen = "127.0.0.1:${toString generated.attic.localPort}";
      storage = {
        bucket = generated.attic.r2.bucket;
        credentials = {
          access_key_id = generated.attic.r2.accessKeyId;
          secret_access_key = generated.attic.r2.secretAccessKey;
        };
        endpoint = "https://${generated.attic.r2.accountId}.r2.cloudflarestorage.com";
        region = "auto";
        type = "s3";
      };
    };
  };

  systemd.services.atticd.serviceConfig = {
    DynamicUser = lib.mkForce false;
    Group = atticUser;
    User = atticUser;
  };

  systemd.services.attic-bootstrap = {
    after = ["atticd.service"];
    path = with pkgs; [
      attic-client
      config.services.atticd.package
      coreutils
      curl
      gnused
      jq
      systemd
    ];
    wantedBy = ["multi-user.target"];
    wants = ["atticd.service"];

    script = ''
      set -euo pipefail

      marker="${stateDir}/attic-bootstrap-complete"
      local_endpoint="${atticLocalEndpoint}"
      atticd_config="$(systemctl cat atticd | sed -n 's/^ExecStart=.* -f \([^ ]*\) --mode.*/\1/p')"

      if [[ -f "$marker" ]]; then
        exit 0
      fi

      if [[ -z "$atticd_config" ]]; then
        echo "failed to determine atticd config path from systemd unit" >&2
        exit 1
      fi

      for _ in $(seq 1 30); do
        if curl -fsS --max-time 2 "$local_endpoint" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      if ! curl -fsS --max-time 2 "$local_endpoint" >/dev/null 2>&1; then
        echo "atticd did not become ready at $local_endpoint" >&2
        exit 1
      fi

      root_token="$(${lib.escapeShellArg atticadmBin} -f "$atticd_config" make-token \
        --sub bootstrap-root \
        --validity 24h \
        --pull '*' \
        --push '*' \
        --delete '*' \
        --create-cache '*' \
        --configure-cache '*' \
        --configure-cache-retention '*' \
        --destroy-cache '*')"

      attic login ${atticRemoteName} "$local_endpoint" "$root_token" --set-default

      if ! attic cache info ${lib.escapeShellArg atticCacheScope} >/dev/null 2>&1; then
        attic cache create ${lib.escapeShellArg atticCacheScope} --priority ${toString generated.attic.cachePriority}
      fi

      ${lib.optionalString generated.attic.public ''
        attic cache configure ${lib.escapeShellArg atticCacheScope} --public
      ''}

      if [[ ! -s ${lib.escapeShellArg atticClientTokenFile} ]]; then
        ci_token="$(${lib.escapeShellArg atticadmBin} -f "$atticd_config" make-token \
          --sub github-actions-ci \
          --validity 1y \
          --pull ${lib.escapeShellArg generated.attic.cacheName} \
          --push ${lib.escapeShellArg generated.attic.cacheName})"
        install -D -m 0640 /dev/null ${lib.escapeShellArg atticClientTokenFile}
        printf '%s' "$ci_token" > ${lib.escapeShellArg atticClientTokenFile}
        chown root:${runnerGroup} ${lib.escapeShellArg atticClientTokenFile}
      fi

      cache_config_json="$(curl -fsSL -H "Authorization: Bearer $root_token" "''${local_endpoint}_api/v1/cache-config/${generated.attic.cacheName}")"
      public_key="$(jq -r '.public_key // empty' <<<"$cache_config_json")"

      install -D -m 0644 /dev/null ${lib.escapeShellArg atticPublicKeyFile}
      printf '%s\n' "$public_key" > ${lib.escapeShellArg atticPublicKeyFile}
      chown root:${runnerGroup} ${lib.escapeShellArg atticPublicKeyFile}

      date --iso-8601=seconds > "$marker"
    '';

    serviceConfig = {
      EnvironmentFile = atticEnvironmentFile;
      Type = "oneshot";
    };
  };

  services.cloudflared = {
    enable = true;
    tunnels = {
      "${generated.cloudflareTunnel.id}" = {
        credentialsFile = tunnelCredentialsFile;
        default = "http_status:404";
        ingress = {
          "${generated.attic.domain}" = "http://127.0.0.1:${toString generated.attic.localPort}";
        };
      };
    };
  };

  services.github-runners.runner = {
    enable = true;
    ephemeral = true;
    extraEnvironment = {
      ATTIC_CACHE = generated.attic.cacheName;
      ATTIC_ENDPOINT = atticLocalEndpoint;
      ATTIC_SERVER = atticLocalEndpoint;
      ATTIC_TOKEN_FILE = atticClientTokenFile;
    };
    extraLabels = generated.runner.labels;
    extraPackages = with pkgs; [
      attic-client
      git
      gnutar
      gzip
      nix
    ];
    group = runnerGroup;
    name = generated.runner.name;
    replace = true;
    runnerGroup =
      if generated.runner.group == ""
      then null
      else generated.runner.group;
    tokenFile = runnerTokenFile;
    url = generated.runner.url;
    user = runnerUser;
    workDir = "/var/lib/github-runner/work";
  };

  systemd.services.github-runner-runner = {
    after = [
      "attic-bootstrap.service"
      "atticd.service"
      "${tunnelUnit}.service"
    ];
    wants = [
      "attic-bootstrap.service"
      "atticd.service"
      "${tunnelUnit}.service"
    ];
  };

  system.stateVersion = "25.11";
}
