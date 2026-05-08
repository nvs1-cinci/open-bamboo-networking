#!/usr/bin/env bash
# plugin_runner.sh — single user-facing entry point for the plugin_runner
# shim. Picks the right BambuStudio libbambu_networking.so version,
# rebuilds the C++ bridge against the matching ABI, then exec's it.
#
# `BBL::PrintParams` is passed by value across the ABI boundary and grew
# with versions, so the bridge MUST be compiled with the same ABI macro
# as the plugin's struct layout. We namespace the build dir per ABI
# (`tools/plugin_runner/build-0xMMmmpp/`) so switching --abi just hits
# ninja's cache for that flavour.
#
# Usage: plugin_runner.sh --abi MM.mm.pp [...passthrough flags...]
# See tools/plugin_runner/README.md for the full reference.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${THIS_DIR}/plugin_runner"

die() { printf 'plugin_runner.sh: %s\n' "$*" >&2; exit 64; }
log() { printf 'plugin_runner.sh: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Parse our own flags out of $@; everything we don't recognise is forwarded
# verbatim to the C++ binary.
# ---------------------------------------------------------------------------
ABI=""
PLUGIN_PATH=""
USE_BACKUP_FALLBACK=0
FORCE_DOWNLOAD=0
CACHE_DIR_OVERRIDE=""
PASSTHROUGH=()

while (( $# > 0 )); do
    case "$1" in
        --abi)                  ABI="$2"; shift 2 ;;
        --plugin-path)          PLUGIN_PATH="$2"; shift 2 ;;
        --use-backup-fallback)  USE_BACKUP_FALLBACK=1; shift ;;
        --force-download)       FORCE_DOWNLOAD=1; shift ;;
        --cache-dir)            CACHE_DIR_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
plugin_runner.sh — drive a stock libbambu_networking.so against your printer.

Wrapper-only flags:
    --abi MM.mm.pp            target ABI version (required)
    --plugin-path PATH        use this .so instead of cache/CDN
    --use-backup-fallback     allow ~/.config/BambuStudio/plugins/backup/
                              when the CDN has nothing for --abi
    --force-download          ignore cache, refetch the plugin
    --cache-dir DIR           override ~/.cache/obn-plugin-runner

Everything else is forwarded to plugin_runner. Run `plugin_runner --help`
for the C++ binary's flag reference, or read tools/plugin_runner/README.md.
EOF
            exit 0 ;;
        *)
            PASSTHROUGH+=("$1"); shift ;;
    esac
done

[[ -n "$ABI" ]] || die "--abi MM.mm.pp is required (e.g. --abi 02.05.03)"
[[ "$ABI" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]] || \
    die "bad --abi '$ABI', expected MM.mm.pp"

# Hex form for CMake: 0xMMmmpp (decimal triplets, each 0..255).
IFS='.' read -r A B C <<< "$ABI"
ABI_HEX="$(printf '0x%02x%02x%02x' "$((10#$A))" "$((10#$B))" "$((10#$C))")"
BUILD_DIR="${SRC_DIR}/build-${ABI_HEX}"
BIN="${BUILD_DIR}/plugin_runner"
CACHE_DIR="${CACHE_DIR_OVERRIDE:-${XDG_CACHE_HOME:-$HOME/.cache}/obn-plugin-runner}"

# ---------------------------------------------------------------------------
# Step 1: build the bridge under this ABI.
# ---------------------------------------------------------------------------
mkdir -p "$CACHE_DIR"
if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    log "configuring plugin_runner under ABI=${ABI_HEX} (${BUILD_DIR})"
    if command -v ninja >/dev/null 2>&1; then
        cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
              -DOBN_ABI_VERSION_HEX="$ABI_HEX" >&2
    else
        cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
              -DOBN_ABI_VERSION_HEX="$ABI_HEX" >&2
    fi
fi
log "building plugin_runner (cached under ABI=${ABI_HEX})"
cmake --build "$BUILD_DIR" -j4 >&2

[[ -x "$BIN" ]] || die "build did not produce $BIN"

# ---------------------------------------------------------------------------
# Step 2: resolve the plugin .so. Order: --plugin-path > cache > CDN > backup.
# ---------------------------------------------------------------------------
parse_so_from_dl_json() {
    # Reads one line of {"ok":..,"so_path":..,"version":..,"http":..}
    # and prints `so_path version` on success, returns nonzero otherwise.
    python3 - "$1" <<'PY'
import json, sys
try:
    j = json.loads(sys.argv[1])
except Exception as e:
    print("parse failed:", e, file=sys.stderr); sys.exit(1)
if not j.get("ok"):
    print(j.get("error", "unknown error"), file=sys.stderr); sys.exit(1)
print(j["so_path"], j.get("version", ""))
PY
}

resolve_plugin() {
    local so="" ver=""
    if [[ -n "$PLUGIN_PATH" ]]; then
        [[ -f "$PLUGIN_PATH" ]] || die "--plugin-path '$PLUGIN_PATH' does not exist"
        echo "$PLUGIN_PATH"
        return
    fi

    # Cache hit: any subdir whose version starts with our ABI prefix.
    if (( ! FORCE_DOWNLOAD )); then
        local match
        match=$(ls -1d "$CACHE_DIR"/${ABI}.* 2>/dev/null | head -1 || true)
        if [[ -n "$match" && -f "${match}/libbambu_networking.so" ]]; then
            log "cache hit: ${match}/libbambu_networking.so"
            echo "${match}/libbambu_networking.so"
            return
        fi
    fi

    # CDN attempt via the C++ downloader (so the URL/headers/zip
    # extraction logic stays in one place).
    local dl_args=(--download-only --abi "$ABI" --cache-dir "$CACHE_DIR")
    (( FORCE_DOWNLOAD )) && dl_args+=(--force)
    log "downloading plugin for ABI=${ABI} from api.bambulab.com..."
    local dl_json dl_rc=0
    dl_json=$("$BIN" "${dl_args[@]}" 2>/dev/null) || dl_rc=$?
    if (( dl_rc == 0 )) && [[ -n "$dl_json" ]]; then
        local fields
        if fields=$(parse_so_from_dl_json "$dl_json"); then
            so=$(echo "$fields" | awk '{print $1}')
            ver=$(echo "$fields" | awk '{print $2}')
            log "downloaded plugin version=${ver} -> ${so}"
            echo "$so"
            return
        fi
    fi
    log "CDN failed for ABI=${ABI}"

    # Optional fallback to user's previously-installed plugin.
    if (( USE_BACKUP_FALLBACK )); then
        local backup="$HOME/.config/BambuStudio/plugins/backup/libbambu_networking.so"
        if [[ -f "$backup" ]]; then
            log "fallback: using backup plugin at $backup"
            echo "$backup"
            return
        fi
        die "no backup plugin at $backup either"
    fi

    die "could not resolve a plugin for ABI=${ABI} (CDN failed, no cache hit; pass --use-backup-fallback to try ~/.config/BambuStudio/plugins/backup/)"
}

SO=$(resolve_plugin)

# ---------------------------------------------------------------------------
# Step 3: hand off to the C++ binary with the resolved .so.
# ---------------------------------------------------------------------------
exec "$BIN" --plugin-path "$SO" "${PASSTHROUGH[@]}"
