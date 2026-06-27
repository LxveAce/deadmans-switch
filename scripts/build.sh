#!/usr/bin/env bash
# build.sh — build a Suicide Marauder firmware image (Linux / macOS).
#
# Owner-only DEFENSIVE anti-forensic layer. See docs/SPEC.md (canonical contract),
# docs/SAFETY.md, docs/THREAT-MODEL.md. The Stage-3 self-erase brick primitive is UNVERIFIED
# (docs/SPIKE-PLAN.md); this script defaults to SUICIDE_SAFE_MODE=1 so the destruct chain only
# simulates+logs. A live-brick build requires you to explicitly pass --no-safe-mode AND --tier T2
# (or --allow-live-brick), and is never produced in CI.
#
# Build backend: arduino-cli by default (ESP32Marauder is MIT and arduino-cli-built per
# docs/RESEARCH-DIGEST.md). PlatformIO is supported via --backend pio.
#
# Usage:
#   ./scripts/build.sh --board esp32 --variant fork --tier T1 [options]
#
# Options:
#   --board <class>        esp32 | esp32s2 | esp32s3 | esp32c3 | esp32c6   (default: esp32)
#   --variant <v>          fork | guardian                                 (default: fork)
#   --tier <t>             T1 | T2                                         (default: T1)
#   --input <i>            serial | touch | mini_kb | cardputer | buttons  (default: serial)
#   --safe-mode            force SUICIDE_SAFE_MODE=1 (DEFAULT, simulate only)
#   --no-safe-mode         build a REAL destruct chain (requires --allow-live-brick if brick=1)
#   --allow-live-brick     acknowledge the UNVERIFIED live brick primitive
#   --backend <b>          arduino-cli | pio                               (default: arduino-cli)
#   --sketch <dir>         path to the ESP32Marauder sketch (FORK)         (env: MARAUDER_SKETCH)
#   --out <dir>            output/bundle dir                               (default: build/<board>)
#   --fqbn <fqbn>          override the arduino-cli FQBN
#   -h | --help
#
# Output: an esptool-ready bundle dir containing app.bin + partitions.bin + bootloader.bin +
# boot_app0.bin (the per-board "suicide bundle" the flasher consumes; guardcfg.bin/otadata come
# from host/provision.py at provision time, not build time).
set -euo pipefail

# ----------------------------------------------------------------------------- defaults
BOARD="esp32"
VARIANT="fork"
TIER="T1"
INPUT="serial"
SAFE_MODE=1
ALLOW_LIVE_BRICK=0
BACKEND="arduino-cli"
SKETCH="${MARAUDER_SKETCH:-}"
OUT=""
FQBN=""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARTITIONS_DIR="${REPO_ROOT}/firmware/partitions"

die() { echo "error: $*" >&2; exit 1; }

# ----------------------------------------------------------------------------- args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)            BOARD="$2"; shift 2;;
    --variant)          VARIANT="$2"; shift 2;;
    --tier)             TIER="$2"; shift 2;;
    --input)            INPUT="$2"; shift 2;;
    --safe-mode)        SAFE_MODE=1; shift;;
    --no-safe-mode)     SAFE_MODE=0; shift;;
    --allow-live-brick) ALLOW_LIVE_BRICK=1; shift;;
    --backend)          BACKEND="$2"; shift 2;;
    --sketch)           SKETCH="$2"; shift 2;;
    --out)              OUT="$2"; shift 2;;
    --fqbn)             FQBN="$2"; shift 2;;
    -h|--help)          sed -n '2,40p' "$0"; exit 0;;
    *)                  die "unknown arg: $1 (try --help)";;
  esac
done

# ----------------------------------------------------------------------------- validate
case "$VARIANT" in fork|guardian) ;; *) die "--variant must be fork|guardian";; esac
case "$TIER"    in T1|T2) ;;        *) die "--tier must be T1|T2";; esac
case "$INPUT"   in serial|touch|mini_kb|cardputer|buttons) ;; *) die "--input invalid";; esac
case "$BACKEND" in arduino-cli|pio) ;; *) die "--backend must be arduino-cli|pio";; esac

[[ -z "$OUT" ]] && OUT="${REPO_ROOT}/build/${BOARD}_${VARIANT}_${TIER}"
mkdir -p "$OUT"

# ----------------------------------------------------------------------------- flag assembly
# brick: T1 default 0, T2 default 1 (SPEC §8). brick is meaningful only as a *config* default the
# host bakes into guardcfg; the build flag SUICIDE_TIER_T2 just toggles compile-time expectations
# (Secure Boot/FE + NVS-encryption defaults).
BRICK_DEFAULT=0
[[ "$TIER" == "T2" ]] && BRICK_DEFAULT=1

DEFS=()
if [[ "$VARIANT" == "fork" ]]; then DEFS+=("-DSUICIDE_FORK"); else DEFS+=("-DSUICIDE_GUARDIAN"); fi
[[ "$TIER" == "T2" ]] && DEFS+=("-DSUICIDE_TIER_T2")
if [[ "$SAFE_MODE" -eq 1 ]]; then
  DEFS+=("-DSUICIDE_SAFE_MODE")
else
  # A real destruct build. If brick is on, the UNVERIFIED self-erase primitive is in play.
  if [[ "$BRICK_DEFAULT" -eq 1 && "$ALLOW_LIVE_BRICK" -ne 1 ]]; then
    die "refusing to build a LIVE brick image: pass --allow-live-brick to acknowledge the UNVERIFIED self-erase primitive (docs/SPIKE-PLAN.md), or keep --safe-mode."
  fi
fi
case "$INPUT" in
  serial)    DEFS+=("-DGATE_INPUT_SERIAL");;
  # touch needs SUICIDE_HAVE_TOUCH_KEYBOARD_OBJ to bind Marauder's real touch_keyboard_obj
  # (GateInput_touch.cpp #errors without it). Correct here: the FORK builds against Marauder source.
  touch)     DEFS+=("-DGATE_INPUT_TOUCH" "-DSUICIDE_HAVE_TOUCH_KEYBOARD_OBJ");;
  mini_kb)   DEFS+=("-DGATE_INPUT_MINI_KB");;
  cardputer) DEFS+=("-DGATE_INPUT_CARDPUTER");;
  buttons)   DEFS+=("-DGATE_INPUT_BUTTONS");;
esac

# ----------------------------------------------------------------------------- partition CSV
# GUARDIAN needs 8 MB+ (16 MB preferred); FORK on classic 4 MB uses the committed reference CSV.
if [[ "$VARIANT" == "guardian" ]]; then
  PART_CSV="${PARTITIONS_DIR}/suicide_guardian_16MB.csv"
elif [[ "$BOARD" == "esp32" || "$BOARD" == "esp32s2" || "$BOARD" == "esp32c3" ]]; then
  PART_CSV="${PARTITIONS_DIR}/suicide_4MB.csv"
else
  PART_CSV="${PARTITIONS_DIR}/suicide_16MB.csv"
fi
[[ -f "$PART_CSV" ]] || die "partition CSV not found: $PART_CSV (the partitions/*.csv are filled by another scaffold task)"

# ----------------------------------------------------------------------------- FQBN
if [[ -z "$FQBN" ]]; then
  case "$BOARD" in
    esp32)    FQBN="esp32:esp32:esp32";;
    esp32s2)  FQBN="esp32:esp32:esp32s2";;
    esp32s3)  FQBN="esp32:esp32:esp32s3";;
    esp32c3)  FQBN="esp32:esp32:esp32c3";;
    esp32c6)  FQBN="esp32:esp32:esp32c6";;
    *)        die "no default FQBN for board $BOARD — pass --fqbn";;
  esac
fi

echo "=============================================================="
echo " Suicide Marauder build"
echo "   board     : $BOARD   (fqbn: $FQBN)"
echo "   variant   : $VARIANT"
echo "   tier      : $TIER   (brick default = $BRICK_DEFAULT)"
echo "   input     : $INPUT"
echo "   SAFE_MODE : $SAFE_MODE  $([[ $SAFE_MODE -eq 1 ]] && echo '(simulate only — nothing is destroyed)' || echo '(REAL DESTRUCT CHAIN)')"
echo "   backend   : $BACKEND"
echo "   partitions: $(basename "$PART_CSV")"
echo "   defines   : ${DEFS[*]}"
echo "   out       : $OUT"
echo "=============================================================="

# ----------------------------------------------------------------------------- backend: pio
if [[ "$BACKEND" == "pio" ]]; then
  command -v pio >/dev/null 2>&1 || die "pio not found on PATH (pip install platformio)"
  # PlatformIO reads build_flags from platformio.ini; export the assembled flags so an [env]
  # using ${sysenv.SUICIDE_BUILD_FLAGS} picks them up. Board env name == $BOARD by convention.
  export SUICIDE_BUILD_FLAGS="${DEFS[*]}"
  export SUICIDE_PARTITIONS="$PART_CSV"
  echo "[pio] SUICIDE_BUILD_FLAGS=$SUICIDE_BUILD_FLAGS"
  pio run -e "$BOARD"
  # collect artifacts (paths per the platformio build dir layout)
  PIO_DIR=".pio/build/${BOARD}"
  for f in firmware.bin partitions.bin bootloader.bin; do
    [[ -f "${PIO_DIR}/${f}" ]] && cp "${PIO_DIR}/${f}" "$OUT/"
  done
  [[ -f "${PIO_DIR}/firmware.bin" ]] && cp "${PIO_DIR}/firmware.bin" "$OUT/app.bin"
  echo "[pio] artifacts -> $OUT"
  exit 0
fi

# ----------------------------------------------------------------------------- backend: arduino-cli
command -v arduino-cli >/dev/null 2>&1 || die "arduino-cli not found on PATH"
[[ "$VARIANT" == "fork" && -z "$SKETCH" ]] && \
  die "FORK build needs the ESP32Marauder sketch path: --sketch <dir> or env MARAUDER_SKETCH (with firmware/bootgate hooked in per firmware/integration/INTEGRATION.md)"
SKETCH_DIR="${SKETCH:-${REPO_ROOT}/firmware/guardian}"   # GUARDIAN sketch lives in-repo
[[ -d "$SKETCH_DIR" ]] || die "sketch dir not found: $SKETCH_DIR"

# arduino-cli only compiles sources INSIDE the sketch dir. guardian.ino #includes the shared bootgate
# (BootGate.h/.cpp under firmware/bootgate), so for the GUARDIAN variant we stage the sketch + bootgate
# into a temp sketch dir (named like the .ino) so both the header and its .cpp are present and compiled.
# (The FORK variant already injects bootgate into the Marauder sketch via apply_hook.sh.)
if [[ "$VARIANT" == "guardian" ]]; then
  _ino="$(basename "$(find "$SKETCH_DIR" -maxdepth 1 -name '*.ino' | head -n1)" .ino)"
  [[ -n "$_ino" ]] || die "no .ino found in guardian sketch dir $SKETCH_DIR"
  STAGE="$(mktemp -d)/${_ino}"
  mkdir -p "$STAGE"
  cp -r "$SKETCH_DIR"/. "$STAGE"/
  if [[ -d "${REPO_ROOT}/firmware/bootgate" ]]; then
    cp "${REPO_ROOT}/firmware/bootgate/"*.h "${REPO_ROOT}/firmware/bootgate/"*.cpp "$STAGE"/ 2>/dev/null || true
  fi
  SKETCH_DIR="$STAGE"
fi

# arduino-cli takes a single --build-property gcc flags string; join our -D defines.
EXTRA_FLAGS="${DEFS[*]}"

# Register our custom partition table under the name the ESP32 core expects. arduino-esp32 resolves
# `build.partitions=<name>` to `<core>/tools/partitions/<name>.csv` (there is NO `build.custom_partitions`
# property), so the CSV must physically exist there as suicide.csv before compiling — otherwise the
# core's `cp tools/partitions/suicide.csv` recipe step fails. THAT was the CI build failure.
ARDUINO_DATA="$(arduino-cli config get directories.data 2>/dev/null || true)"
[[ -z "$ARDUINO_DATA" ]] && ARDUINO_DATA="${HOME}/.arduino15"
_registered=0
for pdir in "$ARDUINO_DATA"/packages/esp32/hardware/esp32/*/tools/partitions; do
  if [[ -d "$pdir" ]]; then cp "$PART_CSV" "$pdir/suicide.csv"; _registered=1; fi
done
[[ $_registered -eq 1 ]] || die "could not find an installed esp32 core partitions dir to register $(basename "$PART_CSV") as suicide.csv (is the esp32 core installed?)"

BUILD_PROPS=(
  "--build-property" "build.partitions=suicide"
  "--build-property" "compiler.cpp.extra_flags=${EXTRA_FLAGS}"
  "--build-property" "compiler.c.extra_flags=${EXTRA_FLAGS}"
)

echo "[arduino-cli] compiling $SKETCH_DIR ..."
arduino-cli compile \
  --fqbn "$FQBN" \
  --export-binaries \
  --output-dir "$OUT" \
  "${BUILD_PROPS[@]}" \
  "$SKETCH_DIR"

# Normalize the bundle: arduino-cli exports <sketch>.ino.bin / .bootloader.bin / .partitions.bin.
# Rename to the canonical bundle names the flasher (flasher-integration/PLAN.md) expects.
shopt -s nullglob
for src in "$OUT"/*.ino.bin;            do cp "$src" "$OUT/app.bin"; done
for src in "$OUT"/*.ino.bootloader.bin; do cp "$src" "$OUT/bootloader.bin"; done
for src in "$OUT"/*.ino.partitions.bin; do cp "$src" "$OUT/partitions.bin"; done
shopt -u nullglob

# boot_app0.bin is a fixed core artifact (not chip-specific). Pull it from the installed core.
BOOT_APP0="$(find "${HOME}/.arduino15/packages/esp32" -name boot_app0.bin 2>/dev/null | head -1 || true)"
if [[ -n "$BOOT_APP0" ]]; then
  cp "$BOOT_APP0" "$OUT/boot_app0.bin"
else
  echo "[warn] boot_app0.bin not found in the installed core; the flasher will fetch it from FlashFiles/."
fi

echo "=============================================================="
echo " bundle ready: $OUT"
ls -1 "$OUT"/app.bin "$OUT"/partitions.bin "$OUT"/bootloader.bin "$OUT"/boot_app0.bin 2>/dev/null || true
echo
echo " next: host/provision.py to mint guardcfg.bin + otadata + bundle.json into this dir,"
echo "       then flash via headless-marauder-gui (flasher-integration/PLAN.md)."
[[ "$SAFE_MODE" -eq 1 ]] && echo " NOTE: SAFE_MODE build — the destruct chain only simulates + logs."
echo "=============================================================="
