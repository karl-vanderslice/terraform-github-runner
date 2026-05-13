{
  pkgs,
  runner-src,
  ...
}: {
  imports = [
    "${runner-src}/nixos/runner-image.nix"
  ];

  networking.hostName = "nixos-runner-image-seed";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  users.users.root = {
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIF8cFo2x2VaWteUYqJb44UDPvowZf67uX65jgVaxSoW ezra-device-access"
    ];
  };

  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  boot.loader.efi.canTouchEfiVariables = false;
}
