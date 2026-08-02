{
  description = "Nix flake for the open-bamboo-networking plugin for OrcaSlicer.";

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

  outputs = {
    self,
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
      configured-obn-abi-version = import ./plugin-version.nix;

      mkPackage = {
        system,
        obn-abi-version ? configured-obn-abi-version,
      }:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.callPackage ./package.nix {
          inherit
            cjson-src
            mosquitto-src
            obn-src
            obn-abi-version
          ;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          package = mkPackage { inherit system; };
        in
        {
          default = package;
          open-bamboo-networking = package;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          package = self.packages.${system}.default;
          obn-abi-version = package.obn-abi-version;
          pluginPath = "${package}/plugins/libbambu_networking_${obn-abi-version}.so";

          installer = pkgs.writeShellApplication {
            name = "install-open-bamboo-networking";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.python3
            ];
            text = ''
              target="''${1:-''${ORCA_CONFIG_DIR:-$HOME/.config/OrcaSlicer}}"
              plugin_dir="$target/plugins"
              timestamp="$(date +%Y%m%d-%H%M%S)"

              mkdir -p "$plugin_dir"

              install_library() {
                source_path="$1"
                destination="$plugin_dir/$(basename "$source_path")"

                if [[ -e "$destination" ]]; then
                  cp -a "$destination" "$destination.backup-$timestamp"
                fi

                install -m 0755 "$source_path" "$destination"
                echo "Installed $destination"
              }

              install_library \
                "${package}/plugins/libbambu_networking_${obn-abi-version}.so"
              install_library "${package}/plugins/libBambuSource.so"

              live_source="${package}/plugins/liblive555.so"
              live_destination="$plugin_dir/liblive555.so"
              if [[ ! -e "$live_destination" ]] || \
                 [[ "$(stat -c %s "$live_destination")" -le 65536 ]]; then
                install_library "$live_source"
              else
                echo "Keeping existing vendor live555: $live_destination"
              fi

              conf="$target/OrcaSlicer.conf"
              if [[ ! -f "$conf" ]]; then
                cat >&2 <<MESSAGE
Plugin files were installed, but $conf does not exist.
Launch OrcaSlicer once, close it, and run this installer again so the
network-plugin selection can be patched safely.
MESSAGE
                exit 0
              fi

              python3 - "$conf" "${obn-abi-version}" <<'PYCODE'
import json
import os
import re
import shutil
import stat
import sys
from pathlib import Path

conf = Path(sys.argv[1])
version = sys.argv[2]
original = conf.read_text(encoding="utf-8")
body = re.sub(
    r"(?:\r?\n)+# MD5 checksum[^\r\n]*(?:\r?\n)*\Z",
    "",
    original,
)
data = json.loads(body)
app = data.get("app")
if not isinstance(app, dict):
    raise SystemExit('OrcaSlicer.conf has no top-level JSON object named "app"')

app["installed_networking"] = "true"
app["network_plugin_version"] = version
app["network_plugin_remind_later"] = "true"

skipped = app.get("network_plugin_skipped_versions")
if isinstance(skipped, str):
    app["network_plugin_skipped_versions"] = ";".join(
        item for item in skipped.split(";") if item and item != version
    )

backup = conf.with_name(conf.name + ".obn-bak")
shutil.copy2(conf, backup)
rendered = json.dumps(data, indent=4, ensure_ascii=False)
rendered += "\n# MD5 checksum 00000000000000000000000000000000\n"

temporary = conf.with_name(conf.name + ".obn-tmp")
temporary.write_text(rendered, encoding="utf-8")
os.chmod(temporary, stat.S_IMODE(conf.stat().st_mode))
temporary.replace(conf)

print(f"Patched {conf}")
print(f"Backup: {backup}")
PYCODE

              echo "Orca network plugin version: ${obn-abi-version}"
              echo "Restart OrcaSlicer before opening the Device page."
            '';
          };

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
            program = "${installer}/bin/install-open-bamboo-networking";
          };
          install = {
            type = "app";
            program = "${installer}/bin/install-open-bamboo-networking";
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
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];
            packages = [
              pkgs.gdb
              pkgs.git
            ];

            OBN_CLIENT_TYPE = "orca_slicer";
            OBN_VERSION = configured-obn-abi-version;
            OBN_MOSQUITTO_SOURCE = mosquitto-src;
            OBN_CJSON_SOURCE = cjson-src;
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt-rfc-style
      );

      lib.mkOpenBambooNetworking = mkPackage;
    };
}
