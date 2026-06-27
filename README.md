# Dead Man's Switch

> **Universal anti-forensic dead-man gate for ESP32 security firmware**

[![Release](https://img.shields.io/github/v/release/LxveAce/deadmans-switch?sort=semver)](https://github.com/LxveAce/deadmans-switch/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: ESP32](https://img.shields.io/badge/platform-ESP32-blue)

Successor to [Suicide Marauder](https://github.com/LxveAce/Suicide-Marauder), the original ESP32 anti-forensic wipe system.

---

<!-- STATUS-ROADMAP:START -->
## Status & Roadmap

**Status:** v1.0.0 is shipped with downloadable cross-platform provisioner binaries; the provisioner release pipeline is green. Overall health is steady-but-in-progress — firmware is hardware-validated on classic ESP32 (CYD) only, and the firmware build CI is being brought back online.

**In progress / known issues:**
- Firmware build CI is being repaired and re-enabled (it is currently dormant due to a build-config mismatch).
- The Fork-variant integration tooling (`firmware/integration/apply_hook.sh`) is being authored so the Fork build path is fully reproducible.
- Stage-3 boot-chain handling is validated only on classic ESP32; validation on S2/S3/C3/C6 is pending on sacrificial hardware.
- Windows installer / distributable for the [Cyber Controller](https://github.com/LxveAce/cyber-controller) flasher front end is in progress (reliability + first-run packaging).
- Documentation cleanup: a single canonical serial-command contract is being defined in `docs/SPEC.md` so README, CHANGELOG, firmware, and Cyber Controller agree.

**Roadmap:**
- **Tails OS (amnesiac) flashing** — a host/PC-side imaging flow to write the official Tails image to a removable disk, with mandatory image signature/checksum verification and removable, non-system target confirmation before any write.
- **"Physical key" access gate** — an access gate protecting host/software use, requiring an admin password and/or a minted USB key present (defaults to fail-closed; AND is the high-assurance default, OR is an explicit convenience option).
- Define one canonical serial-command contract in `docs/SPEC.md`.
- Ship `firmware/integration/apply_hook.sh` as a documented Fork integration tool.
- Reconcile install/run docs across the prebuilt binaries and `host/provision.py` from source.
- Expand validated board/firmware support beyond classic ESP32.
<!-- STATUS-ROADMAP:END -->

---

## What it does

A firmware-agnostic **dead-man gate** that sits between power-on and your security firmware. If the operator cannot authenticate — or the hardware kill line is cut — the device obliterates its own flash, SD card, and (optionally) its boot chain before anything can be recovered.

Dead Man's Switch is not tied to any single firmware. The **Guardian** variant works with any ESP32-based firmware — Marauder, GhostESP, Bruce, HaleHound, Meshtastic, or anything else. The **Fork** variant integrates directly into ESP32 Marauder for tighter coupling (and fits all flash sizes, including 4 MB).

> **This is a DEFENSIVE, owner-only tool** — the same category as Kali's LUKS Nuke, GrapheneOS's duress PIN, and BusKill. It is for protecting hardware you own, not for evading lawful process. Read [`docs/SAFETY.md`](docs/SAFETY.md) and [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) before flashing or arming anything.

---

## How it gates

The gate runs once, early in boot, before the host firmware's UI loads. Its behavior is fail-safe by design:

- **Unprovisioned → can never wipe.** A board with no `guardcfg` config behaves like plain firmware. Destruction is physically impossible.
- **Master-disarmed (default) → can never wipe.** The `armed` flag defaults to `0`. Destruct is impossible unless explicitly armed.
- **Correct password always boots and never wipes**, regardless of switch state (after the dead-man pre-check).
- **Wrong password ×N → wipe.** A power-cycle-safe attempt counter is persisted *before* responding, so a mid-attempt reset cannot reset it. The default threshold is **2**.
- **Dead-man line cut → wipe (when armed).** A hardware arming GPIO must read the "armed" level. Cut, unplug, or tamper with the wire and the board wipes.

The full state machine, NVS schema, and invariants are defined in [`docs/SPEC.md`](docs/SPEC.md) — the canonical contract that firmware, host tooling, and partition tables all conform to.

---

## Features

- **ROM SPI bypass brick** — bypasses the IDF flash protection layer via the ESP32's ROM SPI driver to erase the running application from within itself. Hardware-validated on classic ESP32 (CYD 2432S028).
- **Overwrite-then-erase + verify** — forensic-grade wipe of internal partitions: random overwrite, then erase, then **raw-read** verification (`esp_flash_read`) that every byte is `0xFF` — so an erased sector verifies correctly even under Flash Encryption (T2).
- **SD full-LBA raw wipe** — raw sector-level erasure of the entire SD card (LBA 0 through last sector) via the SDMMC host driver, bypassing the filesystem. Multi-pass support with secure-erase patterns; file-level overwrite fallback when raw access is unavailable.
- **Guardian dead-man gate** — standalone, firmware-agnostic factory partition that gates boot, then jumps to an unmodified firmware in OTA. Works with any ESP32-based firmware, not just Marauder.
- **Password parity validation** — PBKDF2-HMAC-SHA256 password challenge at boot, constant-time compared. Plaintext is never stored, never logged, never transmitted. Host-side provisioning only.
- **2-fail wipe** — power-cycle-safe attempt counter persisted before responding. Two wrong passwords and everything wipes. Fails closed: if the counter cannot persist, the gate never degrades to unlimited guesses.
- **GPIO dead-man switch** — hardware arming line tied to a GPIO pin. Cut the wire, unplug, or tamper — the board wipes. Host tooling rejects non-fail-safe pull/level combinations.
- **Brownout hardening** — hardware brownout detection, ADC voltage monitoring, brownout event logging to NVS, and fast-wipe prioritization. A low-voltage boot **suppresses destruction but still requires the correct password** — no free gate skip.
- **Fast wipe mode** — skip the SD wipe and go straight to flash erase + boot brick in seconds. Designed for battery-powered or brownout-prone deployments.
- **Dashboard hooks** — serial command interface (`SM_STATUS`, `SM_INFO`, `SM_FW_VERSION`, `SM_ARM`, `SM_DISARM`, `SM_SET_PASSWORD`, `SM_WIPE`) for remote management by [Cyber Controller](https://github.com/LxveAce/cyber-controller) or any host tool. Arm/disarm/set-password/wipe are password-authenticated.
- **Multiple input backends** — serial (default, headless), on-screen touch keypad, M5StickC buttons, M5Cardputer QWERTY, and Marauder Mini joystick gate-input drivers.

---

## Supported Boards

| Board | Status | Notes |
|-------|--------|-------|
| ESP32 classic (Gold, CYD, DevKit) | **Hardware-validated** | ROM SPI bypass confirmed. Full wipe + brick verified on a blank classic ESP32 and on CYD 2432S028. |

The Guardian standalone gate was hardware-validated on a blank classic ESP32 — a wrong-password trigger over serial obliterated the entire flash (bootloader, partition table, app, and config all read back as `0xFF`). See [`docs/HARDWARE-TEST.md`](docs/HARDWARE-TEST.md).

---

## Planned Board & Firmware Support

| Target | Firmware / Use Case |
|--------|---------------------|
| **ESP32-S3** | Marauder S3, Bruce S3 |
| **ESP32-C3** | Compact boards |
| **ESP32-C6** | Thread / Zigbee boards |
| **Flipper Zero** | Via companion app |
| **Raspberry Pi Pico W** | Standalone gate |
| **Any ESP32-based firmware** | GhostESP, HaleHound, Meshtastic, and others via Guardian variant |

The Guardian variant is inherently firmware-agnostic — it gates boot at the factory partition level and jumps to whatever firmware lives in OTA. Adding a new board means adding its chip-specific ROM SPI entry points and partition layout; the gate logic itself is universal.

---

## Variants

### Fork *(default — all flash sizes, including 4 MB)*
The gate is compiled **into** a fork of ESP32Marauder and called early from `setup()`, reusing Marauder's own display/keyboard/SD drivers so the password prompt works on every hardware class with almost no new UI code. Self-destruct erases every other partition, the SD, and finally its own boot chain.

### Guardian *(firmware-agnostic — 8 MB+ only)*
A separate tiny **factory** app gates boot, then sets the boot partition and restarts into an **unmodified** firmware in `ota_0`. This gives a cleaner GPL boundary and a cleaner brick (the gate is not erasing its own running region until the very end, and can re-assert via factory fallback). It does not fit in 4 MB — 8 MB minimum, 16 MB preferred.

---

## Tiers

### T1 (default)
No Secure Boot / Flash Encryption. The board is data-wiped but **reflashable**. Good for dev/demo and most threat models.

### T2 (opt-in, IRREVERSIBLE)
Secure Boot v2 + Flash Encryption release mode + `brick=1`. The gate cannot be reflashed past and the erased ciphertext is meaningless. eFuse burns are **permanent**.

---

## Safety: SAFE_MODE by default

Every build script and CI job defaults to `SUICIDE_SAFE_MODE=1`. In SAFE_MODE the entire detect → arm → trigger → erase chain runs against a dedicated **scratch** partition with a dummy key and only **logs** the simulated destruction — it never touches a live partition. If a SAFE_MODE build's partition table has no `scratch` partition, the firmware refuses to simulate (it logs an error and performs **zero** erases).

A real destruct chain requires explicitly passing `--no-safe-mode`, and a live-brick build requires `--allow-live-brick` on top of that. **CI never produces a live-brick build** — the Stage-3 self-erase-of-the-running-app primitive is the one UNVERIFIED capability and is only ever exercised by hand on a sacrificial board (see [`docs/SPIKE-PLAN.md`](docs/SPIKE-PLAN.md)).

---

## Cyber Controller Integration

Dead Man's Switch is designed to be integrated into [Cyber Controller](https://github.com/LxveAce/cyber-controller) as a **git submodule**. Cyber Controller provides:

- Remote arm/disarm and status monitoring via serial dashboard
- Host-side password provisioning (plaintext never touches the device)
- One-click flash of Dead Man's Switch builds to connected boards
- Cross-device coordination — wipe triggers can cascade across multiple devices

---

## Quickstart

1. **Read the safety docs first** — [`docs/SAFETY.md`](docs/SAFETY.md), [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md).
2. **Understand the contract** — [`docs/SPEC.md`](docs/SPEC.md) is the single source of truth for names, NVS keys, offsets, build flags, and the state machine.
3. **Build in SAFE MODE** — `scripts/build.ps1` (Windows) or `scripts/build.sh` (Linux/macOS), which default to `SUICIDE_SAFE_MODE=1`:
   ```sh
   ./scripts/build.sh --board esp32 --variant fork --tier T1
   ```
   Options: `--board {esp32|esp32s2|esp32s3|esp32c3|esp32c6}`, `--variant {fork|guardian}`, `--tier {T1|T2}`, `--input {serial|touch|mini_kb|cardputer|buttons}`, `--backend {arduino-cli|pio}`.
4. **Provision a device** — `host/provision.py` (password via stdin/getpass, **never argv**) produces a `guardcfg.bin` NVS image, a `bundle.json` flash manifest, and (Guardian only) a blank `otadata.bin`.
5. **Flash** — either via CI bundle artifacts, or through [Cyber Controller](https://github.com/LxveAce/cyber-controller) / [Headless Marauder GUI](https://github.com/LxveAce/headless-marauder-gui).

The host provisioner needs only the Python 3.9+ standard library for everything security-relevant; its one external dependency is the NVS partition image generator (`esp-idf-nvs-partition-gen`, pinned in [`host/requirements.txt`](host/requirements.txt)).

---

## Layout

```
deadmans-switch/
├── README.md                      <- you are here
├── CHANGELOG.md / SECURITY.md / CONTRIBUTING.md / LICENSE
├── .github/workflows/             <- CI matrix -> per-board SAFE_MODE bundles
├── docs/
│   ├── SPEC.md                    <- canonical interface contract (source of truth)
│   ├── SAFETY.md                  <- read before flashing / arming / testing
│   ├── THREAT-MODEL.md
│   ├── ARCHITECTURE.md
│   ├── HARDWARE.md                <- wiring guides
│   ├── PROVISIONING.md
│   ├── RESEARCH-DIGEST.md
│   ├── SPIKE-PLAN.md              <- sacrificial-board plan for the UNVERIFIED brick
│   ├── HARDWARE-TEST.md           <- validation log (classic ESP32)
│   └── LICENSING.md               <- GPL/LGPL distribution notes
├── firmware/
│   ├── bootgate/                  <- gate headers + impl + input drivers
│   ├── guardian/                  <- standalone firmware-agnostic gate
│   ├── integration/               <- Marauder fork hook point
│   ├── partitions/                <- 4 MB / 8 MB / 16 MB / Guardian partition CSVs
│   └── test_harness/              <- SAFE_MODE bench
├── host/
│   └── provision.py               <- builds guardcfg.bin + bundle.json
├── scripts/
│   ├── build.ps1 / build.sh       <- parameterized build (board/variant/tier/input)
│   └── build_test_harness.{ps1,sh}
└── flasher-integration/
    └── PLAN.md
```

---

## Credits & License

Built on **[ESP32Marauder](https://github.com/justcallmekoko/ESP32Marauder)** by **justcallmekoko** — the display/keyboard/SD drivers and the entire base firmware are theirs. This project is an additive, owner-only defensive layer on top of that work.

Originally developed as **[Suicide Marauder](https://github.com/LxveAce/Suicide-Marauder)** — the first ESP32 anti-forensic wipe system with boot password gating, automatic wipe on failed attempts, and a hardware dead-man switch. Dead Man's Switch is the universal successor with expanded board and firmware support.

This project is released under the **[MIT License](LICENSE)**. ESP32Marauder is MIT; distribution notes for the LGPL components statically linked in (e.g. ESPAsyncWebServer) are tracked in [`docs/LICENSING.md`](docs/LICENSING.md) — read it before redistributing any binaries.

---

## Connect

- **Discord:** [discord.gg/lxveace](https://discord.gg/lxveace) — questions, help, or to talk through this project
- **GitHub:** [@LxveAce](https://github.com/LxveAce)
- **Website:** [lxveace.com](https://lxveace.com)
- **Project site:** [cybercontroller.org](https://cybercontroller.org)
