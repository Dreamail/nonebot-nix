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
      url = "github:Dreamail/maimai-updater/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      perSystem =
        {
          inputs',
          pkgs,
          ...
        }:
        let
          inherit (inputs) pyproject-nix uv2nix pyproject-build-systems;
          inherit (pkgs) lib;

          python = pkgs.python310;

          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          uv-links = pkgs.symlinkJoin {
            name = "uv-links";
            paths = [
              inputs'.maimai-updater.packages.maimai-pageparser.dist
              inputs'.maimai-updater.packages.nonebot-plugin-maimai-updater.dist
            ];
          };
          maimaiUpdaterOverlay = final: prev: {
            maimai-pageparser = prev.maimai-pageparser.overrideAttrs (old: {
              buildInputs =
                (old.buildInputs or [ ]) ++ inputs'.maimai-updater.packages.maimai-pageparser.buildInputs;
              src = inputs'.maimai-updater.packages.maimai-pageparser.dist;
            });
            nonebot-plugin-maimai-updater = inputs'.maimai-updater.packages.nonebot-plugin-maimai-updater;
          };

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                lib.composeManyExtensions [
                  pyproject-build-systems.overlays.default
                  overlay
                  maimaiUpdaterOverlay
                ]
              );
        in
        {
          _module.args = {
            pkgs = import nixpkgs {
              config.allowUnfree = true;
            };
          };

          packages = rec {
            nonebot2-nix = pythonSet.mkVirtualEnv "nonebot2-nix-env" workspace.deps.default;
            default = nonebot2-nix;
          };

          devShells.default =
            let
              editableOverlay = workspace.mkEditablePyprojectOverlay {
                root = "$REPO_ROOT";
              };
              editablePythonSet = pythonSet.overrideScope editableOverlay;
              virtualenv = editablePythonSet.mkVirtualEnv "nonebot2-nix-dev-env" workspace.deps.all;

            in
            pkgs.mkShell {
              packages = [
                virtualenv
                pkgs.uv
              ];

              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = "${virtualenv}/bin/python";
                UV_PYTHON_DOWNLOADS = "never";
              };

              shellHook = ''
                # Undo dependency propagation by nixpkgs.
                unset PYTHONPATH

                # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
                export REPO_ROOT=$(git rev-parse --show-toplevel)

                ln -sfn ${uv-links} .uv-links
                export UV_FIND_LINKS=$(realpath -s .uv-links)
              '';
            };
        };
    };
}
