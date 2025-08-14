{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    maimai-updater = {
      url = "github:Dreamail/maimai-updater";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{ moduleWithSystem, ... }:
      {
        systems = nixpkgs.lib.systems.flakeExposed;
        perSystem =
          {
            self',
            inputs',
            pkgs,
            ...
          }:
          let
            inherit (inputs) pyproject-nix uv2nix pyproject-build-systems;
            python = pkgs.python310;
          in
          {
            _module.args = {
              pkgs = import nixpkgs {
                config.allowUnfree = true;
              };
            };

            packages = {
              default = pkgs.callPackage ./nix/package.nix {
                inherit
                  uv2nix
                  pyproject-nix
                  pyproject-build-systems
                  python
                  ;
                extraDependencies = [
                  inputs'.maimai-updater.packages.maimai-pageparser
                  inputs'.maimai-updater.packages.nonebot-plugin-maimai-updater
                ];
              };
            };

            devShells.default = self'.packages.default.devShell;
          };

        flake = {
          nixosModules.default = moduleWithSystem (
            perSystem@{ self' }:
            import ./nix/module.nix {
              package = self'.packages.default;
            }
          );
        };
      }
    );
}
