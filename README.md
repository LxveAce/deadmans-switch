# Dead Man's Switch

> **Universal anti-forensic dead-man gate for ESP32 security firmware**

Successor to [Suicide Marauder](https://github.com/LxveAce/Suicide-Marauder), the original ESP32 anti-forensic wipe system.

---

## What it does

A firmware-agnostic **dead-man gate** that sits between power-on and your security firmware. If the operator cannot authenticate — or the hardware kill line is cut — the device obliterates its own flash, SD card, and (optionally) its boot chain before anything can be recovered.

Dead Man's Switch is not tied to any single firmware. The **Guardian** variant works with any ESP32-based firmware — Marauder, GhostESP, Bruce, HaleHound, Meshtastic, or anything else. The **Fork** variant integrates directly into ESP32 Marauder for tighter coupling.

> **This is a DEFENSIVE, owner-only tool** — the same category as Kali's LUKS Nuke, GrapheneOS's duress PIN, and BusKill. Read [`docs/SAFETY.md`](docs/SAFETY.md) and [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) before flashing or arming anything.

---

## Features

- **ROM SPI bypass brick** — bypasses the IDF flash protection layer via the ESP32's ROM SPI driver to erase the running application from within itself. Hardware-validated on classic ESP32 (CYD board).
- **Overwrite-then-erase verify** — forensic-grade wipe: random overwrite, then erase, then raw-read verification that every byte is `0xFF`.
- **SD full-LBA wipe** — raw sector-level erasure of the entire SD card (LBA 0 through last sector), bypassing the filesystem. Multi-pass support with secure-erase patterns.
- **Guardian dead-man gate** — firmware-agnostic factory partition that gates boot, then jumps to an unmodified firmware in OTA. Works with any firmware, not just Marauder.
- **Password parity validation** — PBKDF2-HMAC-SHA256 password challenge at boot. Plaintext never stored, never logged, never transmitted. Host-side provisioning only.
- **2-fail wipe** — power-cycle-safe attempt counter persisted before responding. Two wrong passwords and everything wipes.
- **GPIO dead-man switch** — hardware arming line tied to a GPIO pin. Cut the wire, unplug, or tamper — the board wipes.
- **Brownout hardening** — multi-layer protection against low-voltage conditions during wipe. Destruction suppressed on brownout, but correct password still required.
- **Fast wipe mode** — skip SD wipe and go straight to flash erase + boot brick in seconds. Designed for battery-powered or brownout-prone deployments.
- **Dashboard hooks** — serial command interface (`SM_STATUS`, `SM_INFO`, `SM_ARM`, `SM_DISARM`, `SM_WIPE`) for remote management by [Cyber Controller](https://github.com/LxveAce/cyber-controller) or any host tool.

---

## Supported Boards

| Board | Status | Notes |
|-------|--------|-------|
| ESP32 classic (Gold, CYD, DevKit) | **Hardware-validated** | ROM SPI bypass confirmed. Full wipe + brick verified on CYD 2432S028. |

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

## Cyber Controller Integration

Dead Man's Switch is designed to be integrated into [Cyber Controller](https://github.com/LxveAce/cyber-controller) as a **git submodule**. Cyber Controller provides:

- Remote arm/disarm and status monitoring via serial dashboard
- Host-side password provisioning (plaintext never touches the device)
- One-click flash of Dead Man's Switch builds to connected boards
- Cross-device coordination — wipe triggers can cascade across multiple devices

---

## Tiers

### T1 (default)
No Secure Boot / Flash Encryption. The board is data-wiped but **reflashable**. Good for dev/demo and most threat models.

### T2 (opt-in, IRREVERSIBLE)
Secure Boot v2 + Flash Encryption release mode + `brick=1`. The gate cannot be reflashed past and the erased ciphertext is meaningless. eFuse burns are **permanent**.

---

## Quickstart

1. **Read the safety docs first** — [`docs/SAFETY.md`](docs/SAFETY.md), [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md).
2. **Understand the contract** — [`docs/SPEC.md`](docs/SPEC.md) is the single source of truth for names, NVS keys, offsets, build flags, and the state machine.
3. **Build in SAFE MODE** — `scripts/build.ps1` (Windows) or `scripts/build.sh` (Linux/macOS), which default to `SUICIDE_SAFE_MODE=1`:
   ```sh
   ./scripts/build.sh --board esp32 --variant fork --tier T1 --safe-mode
   ```
4. **Provision a device** — `host/provision.py` (password via stdin/getpass, **never argv**) produces a `guardcfg.bin`, a blank `otadata.bin`, and a `bundle.json` manifest.
5. **Flash** — either via CI bundle artifacts, or through [Cyber Controller](https://github.com/LxveAce/cyber-controller) / [Headless Marauder GUI](https://github.com/LxveAce/headless-marauder-gui).

---

## Layout

```
deadmans-switch/
├── README.md                      <- you are here
├── .gitignore
├── .github/
│   └── workflows/
│       └── build.yml              <- CI matrix -> per-board SAFE_MODE bundles
├── docs/
│   ├── SPEC.md                    <- canonical interface contract (source of truth)
│   ├── SAFETY.md                  <- read before flashing / arming / testing
│   ├── THREAT-MODEL.md
│   ├── RESEARCH-DIGEST.md
│   ├── SPIKE-PLAN.md              <- sacrificial-board plan for the UNVERIFIED brick
│   ├── HARDWARE-TEST.md           <- SAFE_MODE validation log (classic ESP32)
│   └── LICENSING.md               <- GPL/LGPL distribution notes
├── firmware/
│   ├── bootgate/                  <- gate headers + impl
│   ├── guardian/                  <- standalone firmware-agnostic gate
│   ├── integration/               <- Marauder fork hook point
│   ├── partitions/                <- partition table CSVs
│   └── test_harness/             <- SAFE_MODE bench
├── host/
│   └── provision.py               <- builds guardcfg.bin + bundle.json
├── scripts/
│   ├── build.ps1                  <- parameterized build (board/variant/tier/safe-mode)
│   └── build.sh
└── flasher-integration/
    └── PLAN.md
```

---

## Credits & License

Built on **[ESP32Marauder](https://github.com/justcallmekoko/ESP32Marauder)** by **justcallmekoko** — the display/keyboard/SD drivers and the entire base firmware are theirs. This project is an additive, owner-only defensive layer on top of that work.

Originally developed as **[Suicide Marauder](https://github.com/LxveAce/Suicide-Marauder)** — the first ESP32 anti-forensic wipe system with boot password gating, automatic wipe on failed attempts, and a hardware dead-man switch. Dead Man's Switch is the universal successor with expanded board and firmware support.

ESP32Marauder is MIT; distribution notes for the LGPL components statically linked in (e.g. ESPAsyncWebServer) are tracked in [`docs/LICENSING.md`](docs/LICENSING.md) — read it before redistributing any binaries.
