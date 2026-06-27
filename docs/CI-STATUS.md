# CI status — standalone firmware build (best-effort / known-WIP)

_Last updated: 2026-06-27._

## Summary

The standalone `arduino-cli` firmware build (`.github/workflows/build.yml` → `scripts/build.sh`) is
**best-effort** and currently does not produce binaries in CI. It is marked `continue-on-error: true`
so it does not block the repo, and shows as a yellow warning. **The firmware sources are complete** —
this is an `arduino-esp32` 3.x / `arduino-cli` link-configuration issue, not missing/incomplete code.

The boot-gate firmware is delivered + exercised through **cyber-controller** (which bundles this repo as
a submodule), so end users are unaffected by the standalone-build status.

## What was fixed (real bugs, kept)

These three plumbing bugs were genuine and are fixed in `scripts/build.sh` / `build.yml`; each advanced
the build to the next stage:

1. **Custom partition table not registered.** The build set `build.partitions=suicide` (and a
   non-existent `build.custom_partitions` property) but never placed `suicide.csv` where the core looks
   (`<core>/tools/partitions/suicide.csv`). Now the CSV is copied into the esp32 core partitions dir
   before compiling. (Was: `cp: cannot stat '.../tools/partitions/suicide.csv'`.)
2. **Marauder library deps missing (FORK).** The FORK leg compiles against the full upstream
   ESP32Marauder; its Arduino libs (LinkedList, ArduinoJson, Adafruit/display/GPS) are now installed.
   (Was: `fatal error: LinkedList.h: No such file or directory`.)
3. **bootgate not visible to the GUARDIAN sketch.** `guardian.ino` includes the shared bootgate
   component; it is now compiled as a proper Arduino library via `--library`. (Was: `BootGate.h: No
   such file or directory`.)

## Remaining blocker (needs a Linux + ESP32 toolchain to reproduce)

After the above, the build reaches the **link** stage and fails because the esp32 **core + IDF
libraries are not in the final link**: undefined references to `delay`, `Print::println`,
`esp_restart`, `esp_partition_find_first`, `esp_ota_set_boot_partition`, `nvs_*`, `mbedtls_*` — for
**both** the in-repo GUARDIAN sketch and the upstream FORK. Because core symbols like `delay`/`Print`
are unresolved, this is not about the bootgate sources (which are complete and compile); the link is
simply not pulling in `libcore.a` + the precompiled IDF archives.

### Likely causes to investigate (on a Linux host with the esp32 core installed)

- The `--build-property compiler.cpp.extra_flags=…` / `compiler.c.extra_flags=…` overrides in
  `scripts/build.sh` may clobber flags the arduino-esp32 3.x combine/link recipe depends on. Try
  passing defines a different way (e.g. a `boards.local.txt` / a custom menu, or appending rather than
  replacing) and confirm the core/IDF archives appear in the `recipe.c.combine` link line.
- Confirm `arduino-cli compile --fqbn esp32:esp32:esp32s3 firmware/guardian` links cleanly with NO
  custom build-properties first, then re-introduce them one at a time to find which breaks the link.
- Consider the PlatformIO backend (`scripts/build.sh` already has a `pio` path) for the firmware build,
  which handles the IDF link + multi-file projects more robustly than the bare arduino-cli invocation.

Until then: flash/verify via cyber-controller.
