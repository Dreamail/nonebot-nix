{
  package,
}:
{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  name = package.name;
  cfg = rec {
    inherit (config.services.${name})
      enable
      user
      group
      home
      ;
    env = config.services.${name}.env // {
      LOCALSTORE_CACHE_DIR = "${home}/cache/";
      LOCALSTORE_DATA_DIR = "${home}/data/";
      LOCALSTORE_CONFIG_DIR = "${home}/config/";
    };
  };
in
{
  options.services.${name} = {
    enable = mkEnableOption "nonebot2 ${name} service";
    env = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Environment variables to set for the nonebot2 ${name} service";
      example = {
        DRIVER = "~fastapi+~httpx+~websockets";
        PORT = "10180";
      };
    };
    user = mkOption {
      type = types.str;
      default = "nonebot2";
      description = "User under which the nonebot2 ${name} service will run";
      example = "nonebot2";
    };
    group = mkOption {
      type = types.str;
      default = "nonebot2";
      description = "Group under which the nonebot2 ${name} service will run";
      example = "nonebot2";
    };
    home = mkOption {
      type = types.str;
      default = "/var/lib/${name}";
      description = "Home directory for the nonebot2 ${name} service";
      example = "/var/lib/${name}";
    };
  };
  config =
    let
      envFile = pkgs.writeText "${name}-env" (
        concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${toString v}") cfg.env)
      );
      tools = pkgs.callPackage (import ./tools.nix { inherit cfg envFile; }) { inherit package; };
    in
    mkIf cfg.enable {
      users.groups.${cfg.group} = { };
      users.users.${cfg.user} = {
        inherit (cfg) group home;
        isSystemUser = true;
        createHome = true;
      };
      systemd.services.${name} = {
        description = "nonebot2 ${name} service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${package}/bin/python ${package.entryFile}";
          Restart = "on-failure";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.home;
        };
        environment = {
          ENVFILE = envFile;
        };
      };

      environment.systemPackages = [ tools ];
    };
}
