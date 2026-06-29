# Firmware & Board Coverage — what the boot-gate can protect

> **Scope of this document.** A straight answer to one question: *does the Dead Man's Switch boot-gate
> cover the same boards and firmwares that the [Cyber Controller](https://github.com/LxveAce/cyber-controller)
> flasher can write?* It maps every Cyber Controller firmware profile to its gate-support status, and is
> honest about what is **shipped + hardware-validated**, what is **architecturally supported but not yet
> wired/validated**, and what is **out of scope** for an ESP32 boot-gate. Owner-only, defensive framing
> throughout — see [`SAFETY.md`](SAFETY.md) and [`THREAT-MODEL.md`](THREAT-MODEL.md). Canonical contract:
> [`SPEC.md`](SPEC.md); per-board wiring: [`HARDWARE.md`](HARDWARE.md).

## TL;DR

- **The gate is an ESP32 boot-gate.** It runs in an ESP32 app's `setup()` (FORK) or as an ESP32 `factory`
  app (GUARDIAN). It can only ever protect **ESP32-family** targets.
- **Today, in practice, it is wired into exactly one firmware: ESP32 Marauder** (the FORK variant), and it
  is hardware-validated on **classic ESP32 only**. Everything else is tooling-supported but unvalidated, or
  not yet wired.
- **The GUARDIAN variant is firmware-agnostic by design** and is the supported way to gate *any other ESP32
  firmware* (GhostESP, Bruce, HaleHound, Meshtastic, ESP32-DIV, …). It needs **8 MB+ flash** and the target
  firmware placed in `ota_0`. It is architecturally ready but has only been validated **standalone** (no real
  firmware in `ota_0` yet) — see §4.
- **Non-ESP32 targets cannot be gated by this mechanism at all** — that is 8 of Cyber Controller's 26
  firmware profiles (the BW16/RTL8720 Realtek radios, the Flipper Zero STM32 firmwares, the Raspberry Pi SD
  images, and the Orbic/ADB target). They need entirely different anti-forensic mechanisms (§3).

---

## 1. The two support axes

Coverage is the product of **chip** × **firmware**, and they are independent:

**Chip** (which SoC the gate is compiled for). Tooling status from `host/provision.py` + `scripts/build.*`:

| Chip | Provisioner (`provision.py`) | Firmware build (`build.*`) | Self-brick (SelfDestruct stage 3) | Hardware-validated |
|------|------------------------------|----------------------------|-----------------------------------|--------------------|
| ESP32 (classic / WROOM / PICO) | ✅ | ✅ | ✅ ROM-SPI bypass (ESP32 registers) | ✅ **yes** (CYD 2432S028 + blank dev board) |
| ESP32-S2 | ✅ | ✅ | ⚠️ `esp_flash` fallback only | ❌ |
| ESP32-S3 | ✅ | ✅ | ⚠️ `esp_flash` fallback only | ❌ |
| ESP32-C3 | ✅ | ✅ | ⚠️ fallback | ❌ |
| ESP32-C5 | ✅ (now — 0x2000 bootloader) | ❌ not yet (Marauder C5 port is upstream WIP) | ⚠️ fallback | ❌ |
| ESP32-C6 | ✅ | ✅ | ⚠️ fallback | ❌ |
| ESP32-H2 | ✅ (provisioner only) | ❌ | ⚠️ fallback | ❌ |
| ESP32-P4 / H4 | ❌ (offset 0x2000 noted only) | ❌ | ❌ | ❌ |

> Only **classic ESP32** is hardware-validated end-to-end (wipe + brick). On S2/S3/C3/C5/C6 the gate logic,
> password, dead-man and bulk-erase are expected to work, but the **stage-3 self-brick** falls back to the
> `esp_flash` path (which needs `CONFIG_SPI_FLASH_DANGEROUS_WRITE_ALLOWED`) rather than the validated
> ESP32-only ROM-SPI bypass. Treat non-classic chips as **unverified** until tested on real hardware
> (`FORWARD-PLAN.md` "Dig deeper"; `NIGHT-SESSION-LOG.md`).

**Firmware** (which app the gate attaches to) — covered by the matrix in §2.

---

## 2. Cyber Controller firmware → gate-support matrix

Cyber Controller ships **26 firmware profiles** across 5 flash backends. Status of each under the boot-gate:

### 2a. ESP32 firmwares (esptool backend — 18 profiles): gate-eligible

| Firmware (CC profile) | Typical chip(s) | FORK (compiled-in) | GUARDIAN (factory → `ota_0`) |
|-----------------------|-----------------|--------------------|------------------------------|
| **ESP32 Marauder** (`marauder`) | ESP32 / S2 / S3 / C5 | ✅ **shipped** (the only wired FORK) | ✅ eligible |
| GhostESP (`ghost_esp`) | ESP32 / S3 / C5 / C6 | ⚠️ needs a per-firmware hook | ✅ eligible (8 MB+) |
| Bruce (`bruce`) | ESP32 / S3 / C5 / C6 | ⚠️ needs a hook | ✅ eligible (8 MB+) |
| HaleHound (`halehound`) | ESP32 (CYD) | ⚠️ needs a hook | ✅ eligible (8 MB+) |
| ESP32-DIV (`esp32_div`) | ESP32-S3 / ESP32 | ⚠️ needs a hook | ✅ eligible (8 MB+) |
| Hydra32 / ESP32-Deauther (`hydra32`) | ESP32 DevKit | ⚠️ needs a hook | ✅ eligible (8 MB+) |
| Meshtastic (`meshtastic`) | ESP32-S3 (Heltec) | ⚠️ needs a hook | ✅ eligible (8 MB+) |
| Flock-You (`flock_you`) | ESP32-S3 | ⚠️ needs a hook | ✅ eligible |
| OUI-Spy (`oui_spy`) | ESP32-S3 | ⚠️ needs a hook | ✅ eligible |
| Sky-Spy (`sky_spy`) | ESP32-S3 / C6 | ⚠️ needs a hook | ✅ eligible |
| AirTag Scanner (`airtag_scanner`) | ESP32 / S3 | ⚠️ needs a hook | ✅ eligible |
| Chasing-Your-Tail-NG (`cyt_ng`) | ESP32 | ⚠️ needs a hook | ✅ eligible |
| Minigotchi (`minigotchi`) | ESP32 / S3 | ⚠️ needs a hook | ✅ eligible |
| T-REX (`trex`) | ESP32-S3 (T-Deck) | ⚠️ needs a hook | ✅ eligible |
| MCLite / MeshCore (`mclite`) | ESP32-S3 (T-Deck/T-Watch) | ⚠️ needs a hook | ✅ eligible |
| ESP32 Bit Pirate (`bit_pirate`) | ESP32-S3 | ⚠️ needs a hook | ✅ eligible |
| BlueJammer ESP32 (`bluejammer_esp32`)¹ | ESP32 | ⚠️ needs a hook | ✅ eligible |
| Custom / local `.bin` (`custom`) | any ESP32 | n/a (your source) | ✅ eligible if it's an ESP32 app |

For the 17 non-Marauder ESP32 firmwares, **GUARDIAN is the intended path** — it gates them with no source
changes (§4). A **FORK** of any of them is also possible but means authoring that firmware's own
`setup()` insertion hook and (if it has an on-device keyboard) a `GateInput_<class>` adapter bound to *its*
drivers — the parts that are Marauder-specific today (`firmware/integration/`, `GateInput_touch/mini.cpp`).

¹ BlueJammer is flagged **LAB-ONLY / illegal to operate** in Cyber Controller; listed here only for
completeness of the flash set.

### 2b. Non-ESP32 firmwares (8 profiles): out of scope for this gate

| Firmware (CC profile) | Target | Backend | Why the ESP32 boot-gate cannot apply |
|-----------------------|--------|---------|--------------------------------------|
| BW16 Deauther / Vampire (`rtl8720`) | RTL8720DN / BW16 | `rtl8720` | Realtek AmebaD, not Espressif — no `esp_restart`, no ESP32 NVS/mbedtls, different ROM loader (km0/km4/image2) |
| BlueJammer BW16 (`bluejammer_bw16`)¹ | RTL8720DN / BW16 | `rtl8720` | same AmebaD platform |
| Flipper Zero — Momentum (`flipper_momentum`) | STM32WB55 | `qflipper` | STM32, flashed via qFlipper; no ESP32 boot path |
| Flipper Zero — Unleashed (`flipper_unleashed`) | STM32WB55 | `qflipper` | STM32 |
| Pwnagotchi (`pwnagotchi`) | Raspberry Pi (ARM) | `sd_backend` | Linux SD image — not an MCU boot-gate problem |
| RaspyJack (`raspyjack`) | Raspberry Pi (ARM) | `sd_backend` | Linux SD image |
| Kali Linux ARM (`kali-arm`) | Raspberry Pi (ARM64) | `sd_backend` | Linux SD image |
| RayHunter (`rayhunter`) | Orbic RC400L (Android/Qualcomm) | `adb` | Android over ADB; no ESP32 |

These are **~31 % of Cyber Controller's flash set and span 4 of its 5 backends.** An anti-forensic layer for
them is a *different project per platform*, not a port of this gate — see §3.

---

## 3. What a real equivalent would take on the non-ESP32 targets

The gate's *concept* (fail-safe dead-man + duress wipe) can exist on other platforms, but none of this gate's
code is reusable there:

- **RTL8720DN / BW16 (Realtek AmebaD):** would need an AmebaD secure-boot / KM0 bootloader hook and the
  Realtek flash-erase primitives — a separate firmware effort on the Ameba SDK.
- **Flipper Zero (STM32WB55):** STM32 RDP (readout protection) + a FAP/firmware-side PIN gate; the Flipper
  already has its own pin lock. Out of scope.
- **Raspberry Pi SD images:** this is a full-disk-encryption problem (LUKS + a dead-man unlock), handled at
  the Linux layer, not a boot-gate. The repo's roadmap notes a **host-side** "amnesiac Tails" direction
  (`FORWARD-PLAN.md` Directive 1) which is the right home for SBC/PC anti-forensics.
- **Orbic / Android (ADB):** Android FDE/FBE + a wipe trigger; again a platform-native problem.

The honest answer for these eight: **not supported, and not a "port" — they need their own mechanisms.**

---

## 4. The supported way to add any other ESP32 firmware: GUARDIAN

GUARDIAN is firmware-agnostic by construction (`firmware/guardian/`, `SPEC.md` §1). The gate is a tiny app in
the **`factory`** partition; your chosen firmware lives unmodified in **`ota_0`**. On a correct password (and
an armed/disarmed check) the Guardian calls `esp_ota_set_boot_partition(ota_0)` + `esp_restart()` into it; on a
duress trigger it wipes before anything boots. Nothing links against the host firmware.

**Recipe (no firmware source changes):**

1. **Flash budget:** GUARDIAN needs **8 MB+** (16 MB preferred — `suicide_guardian_16MB.csv`). 4 MB boards
   are **FORK-only**, which is why 4 MB targets are effectively Marauder-only today.
2. **Get the firmware as an `ota_0` app image.** Use the single application `.bin` for your chip (the same
   one Cyber Controller would flash at the app offset) — e.g. a GhostESP or Bruce release build.
3. **Provision** the gate config and bundle for your chip:
   ```sh
   python host/provision.py --variant guardian \
     --partitions firmware/partitions/suicide_guardian_16MB.csv \
     --chip <esp32|esp32s3|esp32c5|...> --armed 0 --deadman 1 \
     --arm-pin <non-strapping GPIO> --arm-level 1 --arm-pull 2
   ```
   (C5 is now provisionable — bootloader offset resolves to 0x2000 automatically.)
4. **Flash** `factory`=Guardian + `ota_0`=your firmware + `guardcfg` together (Cyber Controller's suicide
   flash path, or `esptool` from the `bundle.json` manifest). A board with no `guardcfg` is **unprovisioned**
   and can never wipe — the safe default.
5. **Validate in `SUICIDE_SAFE_MODE` first** on a sacrificial board (`INTEGRATION.md` §6) before any real wipe.

**Honest status:** GUARDIAN has been hardware-validated **standalone** (a blank ESP32: wrong-password ×2 wiped
the whole flash to `0xFF`), but **no non-Marauder firmware has actually been placed in `ota_0` and validated
end-to-end yet** (`guardian.ino` simulates the handoff). Wiring and validating one real non-Marauder firmware
(GhostESP or Bruce is the obvious first) is the open task that turns "architecturally supported" into
"shipped." There is also a known anti-skip requirement: without Secure Boot v2 + rollback config, an attacker
who can write flash can rewrite `otadata` to boot `ota_0` directly and skip the Guardian (`INTEGRATION.md` §5/§10).

---

## 5. Summary

| Question | Answer |
|----------|--------|
| Does the gate cover every board Cyber Controller flashes? | **Chips:** all of CC's ESP32 chips are *provisionable* (incl. C5 now); only **classic ESP32** is hardware-validated. **Non-ESP32 boards: no.** |
| Does it cover every firmware Cyber Controller flashes? | **No.** 1 of 18 ESP32 firmwares (Marauder) is wired today; the other 17 are GUARDIAN-eligible but not yet wired/validated; the 8 non-ESP32 firmwares are out of scope. |
| Can we add the rest? | **ESP32 firmwares: yes**, via GUARDIAN (no source changes, 8 MB+) or a per-firmware FORK hook — pending one real end-to-end hardware validation. **Non-ESP32: no** (needs separate platform-native mechanisms). |

_Last updated: 2026-06-29. Grounded in `HARDWARE.md`, `SPEC.md`, `INTEGRATION.md`, `host/provision.py`, and the
Cyber Controller profile registry (`src/config/profiles/`, `src/core/flash_core.py`)._
