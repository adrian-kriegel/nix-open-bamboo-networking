{
  description = "Open Bamboo Networking packages and patched slicer overlay.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    obn-src = {
      url = "github:ClusterM/open-bamboo-networking/v1.1.0";
      flake = false;
    };

    mosquitto-src = {
      url = "github:eclipse-mosquitto/mosquitto/v2.1.2";
      flake = false;
    };

    cjson-src = {
      url = "github:DaveGamble/cJSON/v1.7.18";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      obn-src,
      mosquitto-src,
      cjson-src,
      ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      configured-orca-plugin-version = import ./plugin-version.nix;

      obn-overlay = import ./overlays/open-bamboo-networking.nix {
        inherit
          cjson-src
          mosquitto-src
          obn-src
          ;
        orca-plugin-version = configured-orca-plugin-version;
      };

      orca-slicer-overlay = import ./overlays/orca-slicer.nix;
      bambu-studio-overlay = import ./overlays/bambu-studio.nix;

      allOverlays = lib.composeManyExtensions [
        obn-overlay
        orca-slicer-overlay
        bambu-studio-overlay
      ];

      pkgsFor = system: import nixpkgs { inherit system; overlays = [ allOverlays ]; };

      mkPackage =
        {
          system,
          client ? "orca",
          obn-abi-version ? null,
        }:
        let
          pkgs = import nixpkgs { inherit system; };
          bambu-version-parts = lib.take 3 (lib.splitString "." pkgs.bambu-studio.version);
          default-plugin-version =
            if client == "orca" then
              configured-orca-plugin-version
            else
              "${lib.concatStringsSep "." bambu-version-parts}.99";
          resolved-plugin-version =
            if obn-abi-version == null then default-plugin-version else obn-abi-version;
        in
        pkgs.callPackage ./package.nix {
          inherit
            cjson-src
            client
            mosquitto-src
            obn-src
            ;
          obn-abi-version = resolved-plugin-version;
        };
    in
    {
      overlays = {
        default = obn-overlay;
        all = allOverlays;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.open-bamboo-networking;
          open-bamboo-networking-orca-slicer = pkgs.open-bamboo-networking-orca-slicer;
          open-bamboo-networking-bambu-studio = pkgs.open-bamboo-networking-bambu-studio;
          orca-slicer = pkgs.orca-slicer;
          bambu-studio = pkgs.bambu-studio;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          package = pkgs.open-bamboo-networking-orca-slicer;
          pluginPath = "${package}/plugins/${package.plugin-filename}";

          status = pkgs.writeShellApplication {
            name = "obn-status";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              usage() {
                echo "usage: obn-status <printer-ip> <printer-serial> [access-code]" >&2
                echo "       or set OBN_PRINTER_IP, OBN_PRINTER_SERIAL, OBN_ACCESS_CODE" >&2
              }

              if [[ $# -gt 3 ]]; then
                usage
                exit 2
              fi

              export OBN_PRINTER_IP="''${1:-''${OBN_PRINTER_IP:-}}"
              export OBN_PRINTER_SERIAL="''${2:-''${OBN_PRINTER_SERIAL:-}}"
              if [[ $# -ge 3 ]]; then
                export OBN_ACCESS_CODE="$3"
              fi

              if [[ -z "$OBN_PRINTER_IP" || -z "$OBN_PRINTER_SERIAL" ]]; then
                usage
                exit 2
              fi

              if [[ -z "''${OBN_ACCESS_CODE:-}" ]]; then
                read -r -s -p "Printer access code: " OBN_ACCESS_CODE
                echo
                export OBN_ACCESS_CODE
              fi

              export OBN_TEST_CONFIG_DIR="''${OBN_TEST_CONFIG_DIR:-''${XDG_CACHE_HOME:-$HOME/.cache}/open-bamboo-networking/test}"
              export OBN_LOG_LEVEL="''${OBN_LOG_LEVEL:-debug}"
              export OBN_LOG_STDERR="''${OBN_LOG_STDERR:-1}"
              mkdir -p "$OBN_TEST_CONFIG_DIR"

              exec ${package}/bin/obn-lan-live-test
            '';
          };

          ftps = pkgs.writeShellApplication {
            name = "obn-ftps";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              usage() {
                echo "usage: obn-ftps <printer-ip> [access-code] [local-file] [remote-name]" >&2
                echo "With no local file, this connects and lists the printer root." >&2
              }

              if [[ $# -lt 1 || $# -gt 4 ]]; then
                usage
                exit 2
              fi

              export OBN_PRINTER_IP="$1"
              if [[ $# -ge 2 ]]; then
                export OBN_ACCESS_CODE="$2"
              fi
              if [[ -z "''${OBN_ACCESS_CODE:-}" ]]; then
                read -r -s -p "Printer access code: " OBN_ACCESS_CODE
                echo
                export OBN_ACCESS_CODE
              fi
              if [[ $# -ge 3 ]]; then
                export OBN_UPLOAD_FILE="$3"
              fi
              if [[ $# -ge 4 ]]; then
                export OBN_UPLOAD_NAME="$4"
              fi

              export OBN_LOG_LEVEL="''${OBN_LOG_LEVEL:-debug}"
              export OBN_LOG_STDERR="''${OBN_LOG_STDERR:-1}"
              exec ${package}/bin/obn-ftps-live-test
            '';
          };

          probe = pkgs.writeShellApplication {
            name = "obn-probe";
            text = ''
              exec ${package}/bin/obn-probe-plugin "${pluginPath}"
            '';
          };

          selftest = pkgs.writeShellApplication {
            name = "obn-selftest";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              echo "== ABI and heap-boundary smoke test =="
              ${package}/bin/obn-probe-plugin "${pluginPath}"
              echo
              echo "== Live LAN MQTT pushall test =="
              exec ${status}/bin/obn-status "$@"
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${probe}/bin/obn-probe";
          };
          probe = {
            type = "app";
            program = "${probe}/bin/obn-probe";
          };
          status = {
            type = "app";
            program = "${status}/bin/obn-status";
          };
          ftps = {
            type = "app";
            program = "${ftps}/bin/obn-ftps";
          };
          discover = {
            type = "app";
            program = "${package}/bin/obn-ssdp-listener-test";
          };
          selftest = {
            type = "app";
            program = "${selftest}/bin/obn-selftest";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [
              pkgs.open-bamboo-networking-orca-slicer
              pkgs.open-bamboo-networking-bambu-studio
            ];
            packages = [
              pkgs.gdb
              pkgs.git
            ];

            OBN_ORCA_VERSION = pkgs.open-bamboo-networking-orca-slicer.obn-abi-version;
            OBN_BAMBU_STUDIO_VERSION =
              pkgs.open-bamboo-networking-bambu-studio.obn-abi-version;
            OBN_MOSQUITTO_SOURCE = mosquitto-src;
            OBN_CJSON_SOURCE = cjson-src;
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      lib.mkOpenBambooNetworking = mkPackage;
    };
}
