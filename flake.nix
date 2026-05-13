{
  description = "Terraform Hetzner GitHub runner dev shell";

  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        nixosConfigurations.seed-publisher = inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            runner-src = ./.;
          };
          modules = [
            inputs.disko.nixosModules.disko
            ./.agent-context/nixos-image-seed/disko.nix
            ./.agent-context/nixos-image-seed/hardware-configuration.nix
            ./.agent-context/nixos-image-seed/host.nix
          ];
        };
      };

      perSystem = {
        config,
        system,
        ...
      }: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        preCommit = inputs.git-hooks-nix.lib.${system}.run {
          src = ./.;
          hooks = {
            alejandra.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            terraform_fmt.enable = true;
            terraform_validate.enable = true;
            markdownlint-cli2 = {
              enable = true;
              name = "markdownlint-cli2";
              entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
              language = "system";
              files = "\\.md$";
            };
          };
        };
      in {
        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true;
            deadnix.enable = true;
            statix.enable = true;
          };
        };

        checks.preCommit = preCommit;

        packages =
          if pkgs.stdenv.isLinux
          then {
            nixos-runner-hetzner-image = inputs.nixos-generators.nixosGenerate {
              inherit system;
              format = "qcow";
              modules = [
                ./nixos/runner-image.nix
              ];
            };
          }
          else {};

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            alejandra
            ansible
            attic-client
            attic-server
            bitwarden-cli
            checkov
            deadnix
            gh
            gnutar
            hcloud
            jq
            just
            markdownlint-cli2
            openssh
            pre-commit
            shellcheck
            statix
            terraform
            terraform-docs
            vault
            yamllint
            zensical
          ];

          shellHook = config.pre-commit.installationScript;
        };
      };
    };
}
