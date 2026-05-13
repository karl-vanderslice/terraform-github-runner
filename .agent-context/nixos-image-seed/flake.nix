{
  description = "Temporary ARM NixOS seed image for terraform-github-runner";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    runner-src = {
      url = "path:../..";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    disko,
    runner-src,
    ...
  }: {
    nixosConfigurations.seed = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        inherit runner-src;
      };
      modules = [
        disko.nixosModules.disko
        ./disko.nix
        ./hardware-configuration.nix
        ./host.nix
      ];
    };
  };
}
