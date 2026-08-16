final: prev:
let
  obn-orca = final. open-bamboo-networking-orca-slicer;
in
{
  orca-slicer = prev.orca-slicer.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./patches/orca-slicer.patch ];

    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace \
        src/slic3r/Utils/BBLNetworkPlugin.cpp \
        --replace-fail "@obn_plugin_path@" \
          "${obn-orca.plugin-so}" \
        --replace-fail "@obn_bambu_source_path@" \
          "${obn-orca.bambu-source-so}"

      substituteInPlace src/libslic3r/AppConfig.cpp \
        --replace-fail "@obn_plugin_version@" "${obn-orca.obn-abi-version}"
    '';
  });
}
