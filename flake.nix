{
  description = "Terraform Hetzner GitHub runner dev shell";

  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
        nixosConfigurations.github-runner = inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            ./nixos/disko.nix
            ./nixos/host.nix
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
            biome = {
              enable = true;
              includes = ["*.json"];
            };
            terraform.enable = true;
          };
        };

        checks.preCommit = preCommit;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            alejandra
            ansible
            attic-client
            attic-server
            biome
            checkov
            deadnix
            gh
            gnutar
            hcloud
            jq
            just
            markdownlint-cli2
            inputs.nixos-anywhere.packages.${system}.default
            openssh
            pre-commit
            rbw
            rsync
            shellcheck
            statix
            terraform
            terraform-docs
            yamllint
            zensical
          ];

          shellHook = config.pre-commit.installationScript;
        };
      };
    };
}
