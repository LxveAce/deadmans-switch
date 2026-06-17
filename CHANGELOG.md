# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- **Dashboard hooks** — serial command interface (`SM_STATUS`, `SM_INFO`, `SM_ARM`, `SM_DISARM`, `SM_SET_PASSWORD`, `SM_WIPE`) for remote management by Cyber Controller or any host tool.
- **T1/T2 tier system** — T1 (default): data-wipe, reflashable. T2 (opt-in, IRREVERSIBLE): Secure Boot v2 + Flash Encryption + eFuse burn.
- **Host provisioning tool** — `host/provision.py` builds `guardcfg.bin` + `bundle.json` manifest. Password via stdin/getpass, never argv.
- **Build scripts** — `scripts/build.ps1` (Windows) and `scripts/build.sh` (Linux/macOS) with parameterized board/variant/tier/safe-mode options.
- **CI workflows** — GitHub Actions matrix build producing per-board SAFE_MODE bundles.
- **Multiple input backends** — serial, touch, button, Cardputer keyboard, and mini joystick gate input drivers.
- **Partition table templates** — 4 MB, 8 MB, 16 MB, and Guardian 16 MB partition layouts.
- **Comprehensive documentation** — SPEC.md (canonical contract), SAFETY.md, THREAT-MODEL.md, HARDWARE.md (wiring guides), PROVISIONING.md, ARCHITECTURE.md, RESEARCH-DIGEST.md, SPIKE-PLAN.md, HARDWARE-TEST.md, LICENSING.md.

[1.0.0]: https://github.com/LxveAce/deadmans-switch/releases/tag/v1.0.0
