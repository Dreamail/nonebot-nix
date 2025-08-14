{ cfg, envFile }:
{
  package,
  stdenv,
  pkgs,
}:
stdenv.mkDerivation {
  pname = "${package.name}-tools";
  version = package.version;

  src = ../.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src/pyproject.toml $out/
    cp ${envFile} $out/.env

    cat << EOF > $out/bin/${package.name}-cli
    #!${pkgs.runtimeShell}
    cd $out
    exec sudo -H -u ${cfg.user} ${package}/bin/nb -py ${package}/bin/python "\$@"
    EOF
    chmod +x $out/bin/${package.name}-cli

    runHook postInstall
  '';
}
