final: prev:
let
  obn-bambu = final.open-bamboo-networking-bambu-studio;
  lib = final.lib;
in
{
  bambu-studio-open = prev.bambu-studio.overrideAttrs (oldAttrs: {
    pname = "bambu-studio";

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs =
      (oldAttrs.nativeBuildInputs or [ ])
      ++ (lib.filter (package: (package.pname or package.name or "") == "wxwidgets") (
        oldAttrs.buildInputs or [ ]
      ));

    patches = (oldAttrs.patches or [ ]) ++ [ ./patches/bambu-studio.patch ];

    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace src/slic3r/Utils/NetworkAgent.cpp \
        --replace-fail "@obn_plugin_path@" \
          "${obn-bambu.plugin-so}" \
        --replace-fail "@obn_bambu_source_path@" \
          "${obn-bambu.bambu-source-so}"
    '';
  });
}
