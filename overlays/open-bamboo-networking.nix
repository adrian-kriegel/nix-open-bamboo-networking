{
  obn-src,
  mosquitto-src,
  cjson-src,
  orca-plugin-version,
}:
final: prev:

let
  inherit (final) lib;

  mkPlugin =
    {
      client,
      pluginVersion,
    }:
    final.callPackage ../default.nix {
      inherit
        cjson-src
        client
        mosquitto-src
        obn-src
        ;
      obn-abi-version = pluginVersion;
    };

  bambuVersionParts = lib.take 3 (lib.splitString "." prev.bambu-studio.version);
  bambuPluginVersion = "${lib.concatStringsSep "." bambuVersionParts}.99";

  obn-orca = mkPlugin {
    client = "orca_slicer";
    pluginVersion = orca-plugin-version;
  };

  obn-bambu = mkPlugin {
    client = "bambu_studio";
    pluginVersion = bambuPluginVersion;
  };
in
{
  open-bamboo-networking-orca-slicer = obn-orca;
  open-bamboo-networking-bambu-studio = obn-bambu;
}
