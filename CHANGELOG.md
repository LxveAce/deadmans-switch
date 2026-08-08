# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] — 2026-08-08

### Security

- Zeroize the password buffer on every `build_bundle` exit path, and make the nvs-gen `SystemExit` fallback real so a failed generation can't leave secret material in memory.
- Scrub the password buffer when provisioning validation rejects it, instead of only on the success path.
- Reject passwords that collide with the `wipe` and `sm_` command prefixes at provisioning time, so a chosen password can't shadow a serial command.

### Fixed

- Report the released version in `SM_INFO` — the firmware advertised 1.1.0 while the release was 1.0.0 (PF-8).
- Register the suicide partition CSV into the ESP32 core dir and drop the bogus `build.custom_partitions`, matching `build.sh` so `build.ps1` produces the same layout.
- Reconcile the serial-command contract in the docs with `GateInput_serial.cpp`.
- Repair the firmware build CI: stage the boot-gate sources into the sketch dir, build GUARDIAN against bootgate as a proper Arduino `--library`, and register the custom partition CSV so the core and all bootgate objects link. The standalone firmware build is marked best-effort and non-blocking (known arduino-esp32 3.x core/IDF link issue, diagnosed in `docs/CI-STATUS.md`).
- Make `apply_hook.sh` actually integrate the gate; make `build.ps1` runnable on PowerShell 5.1.

### Added

- Stdlib pytest suite for `provision.py`, plus CI gating for the host provisioner tests and guardcfg size-guard tests.
- Firmware/board coverage matrix against Cyber Controller, including C5 provisioning.
- Canonical `DISCLAIMER.md` with acceptable-use terms (authorized lawful use, as-is / no-warranty / no-liability, not legal advice), linked from the README.
- `.gitattributes` to force LF for shell scripts and CRLF for `.ps1`, for CI robustness across platforms.

### Changed

- Renamed the human-facing name from "Suicide Marauder" to "Dead Man's Switch" across host tooling and firmware strings.
- Named the release provisioner binary `deadmans-switch-provisioner`.
- Overhauled the README to the LxveLabs standard (accuracy, contact, structure), surfaced the PCBWay hardware collaboration, and moved to LxveLabs contacts (discord.gg/lxvelabs, Proton emails, lxvelabs.com) plus a GitHub Sponsors link.
- Removed internal planning and session logs from the public repo, scrubbed hardcoded local paths, and did a voice pass on the prose. Every fact, version, license, and attribution is unchanged.

## [1.0.0] — 2026-06-11

### Added

- **ROM SPI bypass brick** — forensic obliteration via the ESP32's ROM SPI driver, bypassing IDF flash protection. Hardware-validated on classic ESP32 (CYD 2432S028).
- **Overwrite-then-erase + raw-read verify** — forensic-grade wipe: random overwrite, then erase, then raw-read verification that every byte is `0xFF` for all internal partitions.
- **SD full-LBA raw wipe (SDMMC)** — raw sector-level erasure of the entire SD card (LBA 0 through last sector), bypassing the filesystem. Multi-pass support with secure-erase patterns. File-level fallback when raw access is unavailable.
- **Guardian dead-man gate** — standalone firmware-agnostic factory partition that gates boot, then jumps to unmodified firmware in OTA. Works with any ESP32-based firmware (Marauder, GhostESP, Bruce, HaleHound, Meshtastic, etc.). 56-line `.ino`.
- **Fork variant** — gate compiled into ESP32Marauder fork, called early from `setup()`. Works on all flash sizes including 4 MB.
- **Password parity validation** — PBKDF2-HMAC-SHA256 password challenge at boot. Plaintext never stored, never logged, never transmitted. 63B max with whitespace rejection.
- **2-fail wipe** — power-cycle-safe attempt counter persisted before responding. Two wrong passwords triggers full wipe.
- **GPIO dead-man switch** — hardware arming line tied to a GPIO pin. Cut the wire, unplug, or tamper and the board wipes.
- **Brownout hardening** — multi-layer protection: hardware brownout detection, ADC-based voltage monitoring, brownout event logging to NVS, fast_wipe prioritization.
- **Fast wipe mode** — skip SD wipe, go straight to flash erase + boot brick in seconds. Designed for battery-powered or brownout-prone deployments.
- **Dashboard hooks** — serial command interface for remote management by Cyber Controller or any host tool. Read-only `SM_STATUS` / `SM_INFO` return device state and firmware/hardware info; `SM_WIPE` routes into the password-authenticated wipe flow. `SM_ARM` / `SM_DISARM` / `SM_SET_PASSWORD` are recognized but reply that they require re-provisioning from the host (the `armed` flag and password hash live in the `guardcfg` NVS image, which is not modifiable at runtime) — they are not runtime-functional in this release.
- **T1/T2 tier system** — T1 (default): data-wipe, reflashable. T2 (opt-in, IRREVERSIBLE): Secure Boot v2 + Flash Encryption + eFuse burn.
- **Host provisioning tool** — `host/provision.py` builds `guardcfg.bin` + `bundle.json` manifest. Password via stdin/getpass, never argv.
- **Build scripts** — `scripts/build.ps1` (Windows) and `scripts/build.sh` (Linux/macOS) with parameterized board/variant/tier/safe-mode options.
- **CI workflows** — GitHub Actions matrix build producing per-board SAFE_MODE bundles.
- **Multiple input backends** — serial, touch, button, Cardputer keyboard, and mini joystick gate input drivers.
- **Partition table templates** — 4 MB, 8 MB, 16 MB, and Guardian 16 MB partition layouts.
- **Comprehensive documentation** — SPEC.md (canonical contract), SAFETY.md, THREAT-MODEL.md, HARDWARE.md (wiring guides), PROVISIONING.md, ARCHITECTURE.md, RESEARCH-DIGEST.md, SPIKE-PLAN.md, HARDWARE-TEST.md, LICENSING.md.

[Unreleased]: https://github.com/LxveAce/deadmans-switch/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/LxveAce/deadmans-switch/releases/tag/v1.0.1
[1.0.0]: https://github.com/LxveAce/deadmans-switch/releases/tag/v1.0.0
