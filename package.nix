{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  curl,
  openssl,
  zlib,
  uthash,
  obn-src,
  mosquitto-src,
  cjson-src,
  obn-abi-version ? "02.03.00.99",
}:

assert lib.assertMsg
  (builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" obn-abi-version != null)
  "obn-abi-version must have the form MM.mm.pp.rr, for example 02.03.00.99";

stdenv.mkDerivation (finalAttrs: {
  pname = "open-bamboo-networking-orca";
  version = obn-abi-version;

  src = obn-src;

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    curl
    openssl
    uthash
    zlib
  ];

  cmakeBuildType = "RelWithDebInfo";

  cmakeFlags = [
    "-DOBN_CLIENT_TYPE=orca_slicer"
    "-DOBN_VERSION=${obn-abi-version}"
    "-DOBN_RELEASE=ON"
    "-DOBN_PATCH_CLIENT_CONF=OFF"
    "-DOBN_BUILD_TESTS=ON"
  ];

  # Upstream pulls in libmosquitto and cJSON through FetchContent
  preConfigure = ''
    mkdir -p .nix-vendor

    cp -R ${mosquitto-src} .nix-vendor/mosquitto
    cp -R ${cjson-src} .nix-vendor/cjson
    chmod -R u+w .nix-vendor

    cmakeFlagsArray+=(
      "-DFETCHCONTENT_SOURCE_DIR_ECLIPSE_MOSQUITTO=$PWD/.nix-vendor/mosquitto"
      "-DFETCHCONTENT_SOURCE_DIR_CJSON=$PWD/.nix-vendor/cjson"
    )
  '';

  doCheck = true;
  
  checkPhase = ''
    runHook preCheck
    # exclude tests that run agains real devices 
    # those can be run as executables exposed by the main flake
    ctest --output-on-failure -E '^lan_live$'
    runHook postCheck
  '';

  postInstall = ''
    test -f "$out/plugins/libbambu_networking_${obn-abi-version}.so"
    test -f "$out/plugins/libBambuSource.so"

    mkdir -p "$out/share/open-bamboo-networking" "$out/bin"
    printf '%s\n' '${obn-abi-version}' \
      > "$out/share/open-bamboo-networking/orca-plugin-version"

    # install live tests so we can run them manually
    install -m 0755 ./probe_plugin "$out/bin/obn-probe-plugin"
    install -m 0755 ./lan_live_test "$out/bin/obn-lan-live-test"
    install -m 0755 ./ftps_live_test "$out/bin/obn-ftps-live-test"
    install -m 0755 ./ssdp_listener_test "$out/bin/obn-ssdp-listener-test"
  '';

  passthru = {
    inherit obn-abi-version;
  };

  meta = {
    description = "Open-source LAN-first Bambu networking plugin and diagnostics for OrcaSlicer";
    homepage = "https://github.com/ClusterM/open-bamboo-networking";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
