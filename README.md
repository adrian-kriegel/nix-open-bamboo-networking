# open-bamboo-networking 

This repo contains a nix flake for building and installing the open-bamboo-networking plugin for orca slicer.

## Setting ABI Version

Check which plugin version your orca-slicer expects and modify `plugin-version.nix`. 

For the lazy:


```bash
python3 - <<'PY'
import json, pathlib, re
p = pathlib.Path.home() / ".config/OrcaSlicer/OrcaSlicer.conf"
s = re.sub(r"(?:\r?\n)+# MD5 checksum[^\r\n]*(?:\r?\n)*$", "", p.read_text())
print(json.loads(s).get("app", {}).get("network_plugin_version"))
PY
```

TODO: Consume orca-slicer as an input and build against the upstream ABI.

## Install 

The flake comes with an installation utility which modifies your local orca-slicer config. 

e.g. ``~/.config/OrcaSlicer/plugins/`` and ``~/.config/OrcaSlicer/OrcaSlicer.conf``.

```
nix run .#install
``` 

TODO: create a pure installation path via home-manager.

## Build

Build just the plugin (without installation).

```bash
nix build .#open-bamboo-networking
```

Expected output:

```text
result/plugins/libbambu_networking_<version>.so
result/plugins/libBambuSource.so
result/plugins/liblive555.so
```

## Command-line diagnostics

The package builds and installs upstream's standalone diagnostic programs.
They let you exercise the plugin ABI and LAN implementation without launching
OrcaSlicer.

### Validate the built shared library

This `dlopen`s the exact versioned plugin, verifies every expected exported
symbol, creates/destroys an agent, and checks the cross-DSO `std::string`/heap
boundary:

```bash
nix run .#probe
```

### Connect over MQTT and request printer status

This connects to TCP 8883 using the plugin implementation, authenticates as
`bblp`, publishes a `pushall` request, and prints the first report message:

```bash
nix run .#status -- <ip> <serial>
```

The wrapper prompts for the access code without echoing it. It can also be
fully environment-driven:

```bash
export OBN_PRINTER_IP=<ip>
export OBN_PRINTER_SERIAL=<serial>
read -rsp 'Access code: ' OBN_ACCESS_CODE; echo
export OBN_ACCESS_CODE
nix run .#status
```

For maximum logs:

```bash
OBN_LOG_LEVEL=trace OBN_LOG_STDERR=1 \
  nix run .#status -- <ip> <serial>
```

The upstream `lan_live_test` currently prints only the first 400 bytes of the
first `pushall` report. Its main purpose is connection/authentication/status
smoke testing, not a polished status dashboard.

### Test ABI and live MQTT in one command

```bash
nix run .#selftest -- <ip> <serial>
```

### Test FTPS independently

Connect and list the printer's root directory:

```bash
nix run .#ftps -- <ip>
```

Upload a temporary file, list again, and delete it:

```bash
nix run .#ftps -- \
  <ip> \
  "$OBN_ACCESS_CODE" \
  /tmp/test.bin \
  /obn-test.bin
```

### Listen for printer discovery advertisements

Listen for 15 seconds on UDP port 2021:

```bash
nix run .#discover
```

Custom duration and port:

```bash
nix run .#discover -- 30 2021
```

### Important distinction

`obn-probe-plugin` loads and exercises the produced `.so`, but does not connect
to a printer. `obn-lan-live-test` and `obn-ftps-live-test` compile the same
implementation sources directly into their test executables; they validate the
networking implementation but do not route live calls through `dlopen` and the
plugin's exported C ABI.
