{
  pkgs,
  lib,
  ...
}: {
  system.stateVersion = "24.11";

  # Keep cloud-init enabled for metadata handling on cloud images,
  # but runner lifecycle is owned by systemd in the image.
  services.cloud-init.enable = true;

  users.users.runner = {
    isNormalUser = true;
    description = "GitHub Actions runner user";
    extraGroups = ["wheel"];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    jq
    unzip
    bash
  ];

  systemd.services.github-runner-bootstrap = {
    description = "Prepare prebuilt runner image host";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 0755 -o runner -g users /opt/actions-runner
      # The image intentionally does not bake credentials. Runtime registration
      # is handled by cloud-init or by an external first-boot unit with Vault.
    '';
  };

  networking.firewall.enable = true;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };
}
