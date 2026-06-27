#!/usr/bin/env bash
# apply_hook.sh — integrate the Suicide Marauder boot-gate (FORK) into an ESP32Marauder sketch.
#
# Owner-only DEFENSIVE anti-forensic layer. See ../../docs/SPEC.md, ../../docs/SAFETY.md.
# Implements firmware/integration/INTEGRATION.md §1 + §3 deterministically for CI and local use:
#   1. copies firmware/bootgate/* into <marauder>/esp32_marauder/bootgate/  (the include path the
#      patch uses: #include "bootgate/BootGate.h")
#   2. applies esp32marauder.ino.patch (anchor-based, --fuzz=3) to the sketch's .ino, inserting the
#      fail-closed gate hook after display_obj.RunSetup() and before settings_obj.begin().
# Idempotent: re-running on an already-integrated sketch is a no-op for the patch step.
#
# Usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>
#   <marauder_repo_root> : upstream ESP32Marauder checkout (contains esp32_marauder/)
#   <bootgate_src_dir>   : path to firmware/bootgate in THIS repo (e.g. firmware/bootgate)
set -euo pipefail

SKETCH_ROOT="${1:?usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>}"
BOOTGATE_SRC="${2:?usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCRIPT_DIR/esp32marauder.ino.patch"

SKETCH_DIR="$SKETCH_ROOT/esp32_marauder"
INO="$SKETCH_DIR/esp32_marauder.ino"

[ -d "$SKETCH_DIR" ]   || { echo "::error::sketch dir not found: $SKETCH_DIR" >&2; exit 1; }
[ -f "$INO" ]          || { echo "::error::Marauder .ino not found: $INO" >&2; exit 1; }
[ -d "$BOOTGATE_SRC" ] || { echo "::error::bootgate sources not found: $BOOTGATE_SRC" >&2; exit 1; }
[ -f "$PATCH" ]        || { echo "::error::patch not found: $PATCH" >&2; exit 1; }

# 1) Drop the gate sources into the sketch as bootgate/. All GateInput_<class>.cpp adapters are
#    copied; each is #ifdef-guarded on its GATE_INPUT_* define, so only the selected one emits code.
echo "[apply_hook] copying gate sources -> $SKETCH_DIR/bootgate/"
mkdir -p "$SKETCH_DIR/bootgate"
cp "$BOOTGATE_SRC"/*.h "$SKETCH_DIR/bootgate/"
cp "$BOOTGATE_SRC"/*.cpp "$SKETCH_DIR/bootgate/"

# 2) Apply the fail-closed setup() hook (idempotent).
if grep -q 'suicide::BootGate::run()' "$INO"; then
  echo "[apply_hook] boot-gate hook already present — skipping patch"
else
  echo "[apply_hook] applying setup() hook patch (anchor-based, --fuzz=3)"
  patch -p1 --fuzz=3 -d "$SKETCH_ROOT" < "$PATCH"
  grep -q 'suicide::BootGate::run()' "$INO" \
    || { echo "::error::patch applied but gate call not found in $INO" >&2; exit 1; }
fi

echo "[apply_hook] boot-gate integrated into $SKETCH_DIR"
