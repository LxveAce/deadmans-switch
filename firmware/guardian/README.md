# Guardian — standalone universal dead-man gate

`guardian.ino` is the boot-gate with **no host firmware** — proof that the Suicide gate is
**firmware-agnostic**. It runs first, gates (password / dead-man / attempt-count), and on PASS hands off
to whatever firmware lives in `ota_0` (the GUARDIAN model from [`docs/SPEC.md`](../../docs/SPEC.md) §1).
A wrong-password / dead-man trigger runs the same `SelfDestruct` forensic obliteration as the Marauder
FORK. This is the basis of the **universal (board + firmware-specific) dead-man switch**: pair this gate
in `factory` with *any* firmware in `ota_0` (Marauder, Bruce, GhostESP, ESP32-DIV, …).

## Status
**Hardware-validated 2026-06-10** on a blank classic ESP32 (CH340K): a live build + provisioned
`guardcfg` (armed=1, deadman=0, brick=1, max_att=2) + a **wrong-password ×2 trigger over serial**
**obliterated the entire flash** — esptool read-back showed bootloader, partition table, app, and
guardcfg all `0xFF`. Full account in [`docs/NIGHT-SESSION-LOG.md`](../../docs/NIGHT-SESSION-LOG.md).

## Build
The bootgate sources are not duplicated here — stage them next to the sketch (same pattern as
`firmware/test_harness`), then build with arduino-cli (esp32 core 2.0.11):

```bash
# stage: copy ../bootgate/*.{h,cpp} and ../partitions/suicide_4MB.csv (as partitions.csv) next to guardian.ino
arduino-cli compile \
  --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs \
  --build-property "compiler.cpp.extra_flags=-DSUICIDE_FORK -DGATE_INPUT_SERIAL -DARMING_PIN=27 -DARMING_ACTIVE_LEVEL=1 -DARMING_PULL=2" \
  <sketchdir>
```

- **SAFE first:** add `-DSUICIDE_SAFE_MODE` to simulate the wipe (zero erases). A live (non-SAFE) brick
  build is for a **sacrificial board only**.
- **Input adapter:** swap `-DGATE_INPUT_SERIAL` for `-DGATE_INPUT_TOUCH` / `_MINI_KB` / `_CARDPUTER` /
  `_BUTTONS` per the board (touch also needs `-DSUICIDE_HAVE_TOUCH_KEYBOARD_OBJ` + a keyboard wiring).
- Flash `guardian.ino.bin`@0x10000 + the boot chain, then a provisioned `guardcfg.bin`@`<guardcfg off>`
  (`host/provision.py`). With no `guardcfg`, the gate is unprovisioned and boots straight through.

## Anti-skip (T2)
Without Secure Boot, an attacker who can write flash can rewrite `otadata` to boot `ota_0` directly and
skip this gate. Closing that — the "no boot attack bypasses the password" guarantee — requires Secure
Boot v2 + `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` + the gate re-asserting `factory` on boot (SPEC §6,
INTEGRATION.md §6). It is a **T2 (eFuse) property** and IRREVERSIBLE — see the owner-choice C2 in the
night log.
