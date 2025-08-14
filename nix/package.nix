{
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  extraDependencies ? [ ],
  python,
  pkgs,
  lib,
}:
let
  toml = lib.importTOML ../pyproject.toml;
  name = toml.project.name;
  version = toml.project.version;

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ../.; };
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  extraDependenciesOverlay = lib.composeManyExtensions (
    lib.forEach extraDependencies (
      dep: final: prev: {
        ${dep.pname} = prev.${dep.pname}.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ dep.buildInputs;
          src = dep.dist;
        });
      }
    )
  );

  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
          extraDependenciesOverlay
        ]
      );

  uv-links = pkgs.symlinkJoin {
    name = "uv-links";
    paths = lib.forEach extraDependencies (dep: dep.dist);
  };
  editableOverlay = workspace.mkEditablePyprojectOverlay {
    root = "$REPO_ROOT";
  };
  editablePythonSet = pythonSet.overrideScope editableOverlay;

  devShell =
    let
      virtualenv = editablePythonSet.mkVirtualEnv "${name}-dev" workspace.deps.all;
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

  entryFile = pkgs.runCommand "bot.py" { } ''
    touch $out
    echo "import os" >> $out
    echo "import nonebot" >> $out
    ${lib.concatStringsSep "\n" (
      lib.forEach toml.tool.nonebot.adapters (adapter: ''
        echo "from ${adapter.module_name} import Adapter as ${lib.toUpper (lib.last (lib.splitString "." adapter.module_name))}Adapter" >> $out
      '')
    )}
    echo "def main():" >> $out
    echo "    nonebot.init(_env_file=os.environ['ENVFILE'])" >> $out
    echo "    driver = nonebot.get_driver()" >> $out
    ${lib.concatStringsSep "\n" (
      lib.forEach toml.tool.nonebot.adapters (adapter: ''
        echo "    driver.register_adapter(${lib.toUpper (lib.last (lib.splitString "." adapter.module_name))}Adapter)" >> $out
      '')
    )}
    ${lib.concatStringsSep "\n" (
      lib.forEach toml.tool.nonebot.plugins (plugin: ''
        echo "    nonebot.load_plugin('${plugin}')" >> $out
      '')
    )}
    ${lib.concatStringsSep "\n" (
      lib.forEach toml.tool.nonebot.builtin_plugins (builtin_plugin: ''
        echo "    nonebot.load_builtin_plugin('${builtin_plugin}')" >> $out
      '')
    )}
    echo "    nonebot.run()" >> $out
    echo "if __name__ == '__main__':" >> $out
    echo "    main()" >> $out
  '';

  package =
    (pythonSet.mkVirtualEnv name workspace.deps.default).overrideAttrs
      (previousAttrs: {
        inherit version devShell entryFile;
      });
in
package
