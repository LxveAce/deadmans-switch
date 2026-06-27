#!/usr/bin/env bash
# apply_hook.sh - integrate the Dead Man's Switch boot-gate (FORK) into an ESP32Marauder sketch.
#
# Owner-only DEFENSIVE anti-forensic layer. See ../../docs/SPEC.md, ../../docs/SAFETY.md.
# Implements firmware/integration/INTEGRATION.md section 1 + section 2 deterministically:
#   1. copies firmware/bootgate/* into <marauder>/esp32_marauder/bootgate/  (the include path the
#      hook uses: #include "bootgate/BootGate.h")
#   2. inserts the two anchor-based edits into the sketch .ino (idempotent):
#        - the esp_system.h + bootgate/BootGate.h includes, right after #include "lang_var.h"
#        - the FAIL-CLOSED gate call, immediately before settings_obj.begin()
#
# The insertion is done by an anchor match (NOT patch(1)): the repo's esp32marauder.ino.patch is a
# human-readable reference of the change, not a line-numbered unified diff, so `patch` cannot apply
# it. Anchoring on the surrounding code is what makes this line-number tolerant across upstream
# Marauder releases. Re-running on an already-integrated sketch is a no-op.
#
# Usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>
set -euo pipefail

SKETCH_ROOT="${1:?usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>}"
BOOTGATE_SRC="${2:?usage: apply_hook.sh <marauder_repo_root> <bootgate_src_dir>}"

SKETCH_DIR="$SKETCH_ROOT/esp32_marauder"
INO="$SKETCH_DIR/esp32_marauder.ino"

[ -d "$SKETCH_DIR" ]   || { echo "::error::sketch dir not found: $SKETCH_DIR" >&2; exit 1; }
[ -f "$INO" ]          || { echo "::error::Marauder .ino not found: $INO" >&2; exit 1; }
[ -d "$BOOTGATE_SRC" ] || { echo "::error::bootgate sources not found: $BOOTGATE_SRC" >&2; exit 1; }

# 1) Drop the gate sources into the sketch as bootgate/. All GateInput_<class>.cpp adapters are
#    copied; each is #ifdef-guarded on its GATE_INPUT_* define, so only the selected one emits code.
echo "[apply_hook] copying gate sources -> $SKETCH_DIR/bootgate/"
mkdir -p "$SKETCH_DIR/bootgate"
cp "$BOOTGATE_SRC"/*.h "$SKETCH_DIR/bootgate/"
cp "$BOOTGATE_SRC"/*.cpp "$SKETCH_DIR/bootgate/"

# 2) Anchor-based insertion of the includes + fail-closed gate call (idempotent).
python3 - "$INO" <<'PY'
import sys
ino = sys.argv[1]
src = open(ino, encoding="utf-8").read()

if "suicide::BootGate::run()" in src:
    print("[apply_hook] boot-gate hook already present - skipping insertion")
    sys.exit(0)

INC_ANCHOR = '#include "lang_var.h"'
INC_BLOCK = INC_ANCHOR + '''

// === Dead Man's Switch boot-gate (FORK). Owner-only DEFENSIVE duress layer. See docs/SPEC.md. ===
// Sources live in bootgate/ (added to the sketch by apply_hook.sh, per INTEGRATION.md).
#include "esp_system.h"        // esp_restart() - the fail-closed reboot used by the gate hook below
#include "bootgate/BootGate.h"'''

CALL_ANCHOR = '  settings_obj.begin();'
CALL_BLOCK = '''  // === Dead Man's Switch boot-gate call (FORK), per docs/SPEC.md. FAIL-CLOSED. ===
  // unprovisioned / master-disarmed / correct password -> GATE_PASS (boots normally, cannot wipe);
  // anything else reboots instead of leaking into the un-gated Marauder UI. A real (non-SAFE)
  // trigger never returns; SUICIDE_SAFE_MODE only logs a simulated wipe and returns GATE_PASS.
  if (suicide::BootGate::run() != suicide::GATE_PASS) {
    esp_restart();   // never returns; re-runs the gate fail-closed on reboot
  }

''' + CALL_ANCHOR

if INC_ANCHOR not in src:
    sys.exit('::error::include anchor not found: %s' % INC_ANCHOR)
if CALL_ANCHOR not in src:
    sys.exit('::error::call anchor not found: %r' % CALL_ANCHOR)

src = src.replace(INC_ANCHOR, INC_BLOCK, 1)
src = src.replace(CALL_ANCHOR, CALL_BLOCK, 1)
open(ino, "w", encoding="utf-8").write(src)
print("[apply_hook] inserted includes + fail-closed gate call")
PY

grep -q 'suicide::BootGate::run()' "$INO" \
  || { echo "::error::gate call not present in $INO after insertion" >&2; exit 1; }
echo "[apply_hook] boot-gate integrated into $SKETCH_DIR"
