# Autonomous Night Session — Work Log

**Started:** 2026-06-10 (late). Owner (LxveAce) asleep; agent working autonomously for several hours.
**Mandate:** finish + stress-test the Suicide-Marauder wipe across **every** flashable firmware/board
config; research a **universal (board+firmware-specific) dead-man's switch**; refine the **cyber-controller
dashboard** (cross-comm, optional install password, boot-attack hardening); **organize repos**, update
**profile README + project READMEs + websites**; red-team + loop; **log everything**; save owner choices
for next session; never stop — if blocked, work around it or move to other repo work.

This file is the single source of truth to resume. Append-only sections below; newest status at top.

---

## CONNECTED HARDWARE (this session)
- **COM5** — CYD 2432S028 (classic ESP32, USB-SERIAL CH340). Primary test board. Auto-reset works.
- **COM3** — ESP32-WROOM-32 running **ESP-AT v2.4.0** (Silicon Labs CP210x). Headless. **esptool cannot
  auto-enter download mode** ("Wrong boot mode 0x13") — its adapter lacks the auto-program circuit.
  **OWNER CHOICE NEEDED (logged below): a one-time BOOT-button tap is required to flash COM3, OR confirm
  it has no auto-reset.** Workarounds attempted (manual DTR/RTS classic reset, 10 connect-attempts) all
  failed. Until then COM3 can only be read over serial (running firmware identified), not flashed.

## TOOLCHAIN (set up this session, all under `C:\Users\extra\projects\_smbuild\`)
- `arduino-cli.exe` 1.5.1 (`_smbuild/tools/`), data dir `_smbuild/a15` (`ARDUINO_DIRECTORIES_DATA`).
- esp32 Arduino core **2.0.11** (the version Marauder's CI pins; `package_esp32_dev_index.json`).
- 16 pinned Marauder libs cloned to `_smbuild/libs/` (TFT_eSPI V2.5.34 cyd_micro setup, NimBLE 1.3.8,
  etc. — exact refs from ESP32Marauder/.github/workflows/build_parallel.yml).
- platform.txt patched with `-zmuldefs` (Marauder CI requirement for core 2.0.11).
- ESP32Marauder source cloned to `_smbuild/.../ESP32Marauder` → actually `projects/ESP32Marauder`
  (justcallmekoko master, v1.12.2). Suicide gate injected into `esp32_marauder/` (bootgate flat-copied,
  `.ino` patched: includes + `if (suicide::BootGate::run()!=GATE_PASS) esp_restart();` before
  `settings_obj.begin()`; `partitions.csv` = suicide_4MB.csv).
- Build cmd (CYD touch): `arduino-cli compile --fqbn esp32:esp32:d32:PartitionScheme=min_spiffs
  --libraries _smbuild/libs --build-property "compiler.cpp.extra_flags=-DMARAUDER_CYD_MICRO -DSUICIDE_FORK
  -DGATE_INPUT_TOUCH -DSUICIDE_HAVE_TOUCH_KEYBOARD_OBJ -DARMING_PIN=27 -DARMING_ACTIVE_LEVEL=1
  -DARMING_PULL=2" --build-path _smbuild/build_live ESP32Marauder/esp32_marauder`. SAFE build adds
  `-DSUICIDE_SAFE_MODE`; live wipe omits it.
- Flash: core esptool 4.5.1 at `_smbuild/a15/packages/esp32/tools/esptool_py/4.5.1/esptool.exe`,
  `--flash_mode dio --flash_freq 40m`, regions 0x1000 bootloader / 0x8000 partitions / 0xe000 boot_app0
  (`.../2.0.11/tools/partitions/boot_app0.bin`) / 0x10000 app / 0x1F0000 guardcfg.
- Provision guardcfg: `_smbuild/provision_*.py` call `Suicide-Marauder/host/provision.build_bundle`.
- Test helpers: `_smbuild/trigger_capture.py <port> <secs>` (reset→boot→capture serial),
  `_smbuild/gate_probe*.py`.

---

## MAJOR RESULT (verified): forensic obliteration WORKS on the CYD (classic ESP32)
The live-wipe build, triggered via the dead-man path (armed=1, deadman=1, no arming switch on GPIO27),
**obliterated the entire flash**, verified by esptool read-back — ALL regions 0xFF:
`bootloader@0x1000, partition table@0x8000, app(Marauder) 0x10000..0x1F0000 (header+mid+end),
guardcfg@0x1F0000`. Board now boot-loops in the indestructible mask ROM ("invalid header: 0xffffffff")
— **no firmware, no Marauder, no logs, no partition table (the 'guardcfg' tell is gone), nothing
bootable.** The forensic random-overwrite pass runs on the app before the final erase. Recoverable only
by an owner reflash over UART (mask ROM survives) — exactly the design intent (T1, no eFuse burn).

### The hard part that was solved (self-erasing the running app on stock arduino-esp32)
`CONFIG_SPI_FLASH_DANGEROUS_WRITE_ABORTS=y` in core 2.0.11: `esp_flash_erase_region()` abort()s on the
protected boot chain AND on the running app region. The fix (in `firmware/bootgate/SelfDestruct.cpp`
`brickBootChain`, ESP32 path): erase the running app FIRST (it's gone even if a later step fails), via
the **ROM SPI driver** (`esp_rom_spiflash_unlock/erase_sector/write`) inside the IDF flash-only critical
section `spi_flash_disable_interrupts_caches_and_other_cpu()` (declared `extern` — not in a public
header but exported by libspi_flash.a; it disables IRQs + stalls the other core + disables the cache the
*correct* idle-then-clear way — my manual `Cache_Read_Disable` wedged SPI0/SPI1 arbitration). Also
disable RTC + TG0/TG1 watchdogs (register writes) so the multi-second erase isn't reset mid-wipe. Reset
via RTC_CNTL SW_SYS_RST (esp_restart lives in the now-erased app). Debugged with direct-UART markers
(`brickMark`, IRAM-safe) because arduino suppresses ESP_LOG.

**`wipeInternal` (data partitions) already worked** via esp_partition (spiffs/nvs/coredump/guardcfg
erased + overwritten). Only the running-app + boot-chain self-erase needed the ROM bypass.

---

## OPEN BUGS / TODO (firmware)
1. **SD wipe aborts on no-card** (`wipeSDImpl` → `sdmmc_card_init`, SelfDestruct.cpp:~335). On a board
   with `wipe_sd=1` and no card / SPI-only SD, the SDMMC raw path abort()s instead of failing safe.
   Workaround used for the obliteration test: `wipe_sd=0`. FIX NEEDED: guard the SDMMC raw attempt /
   detect card via SD.h first / skip gracefully. (CYD has an SD slot but no card was inserted.)
2. **Debug `brickMark` UART markers** still in `brickBootChain` — REMOVE for the production build (a
   wiping board should emit nothing on serial). Keep only for bring-up.
3. **Per-chip brick** currently ESP32-only (`CONFIG_IDF_TARGET_ESP32`): RTC/TG WDT + RTC_CNTL reset +
   ROM headers are ESP32 register addresses. S2/S3/C3/C6 need their own addresses + `esp32sX/rom/...`.
   Non-ESP32 falls back to the esp_flash path (works only on DANGEROUS_WRITE_ALLOWED builds).
4. **Other chips/boards untested** (only the CYD classic-ESP32 path is hardware-proven).

## OWNER CHOICES TO MAKE (next session — do not block on these)
- **C1 — COM3 headless board:** needs a one-time BOOT-button tap to enter download mode (no auto-reset),
  OR confirm whether it has an auto-program circuit / which pins. Until then it can't be flashed headless.
- **C2 — T2 (eFuse) tier:** the obliteration above is **T1** (reflashable over UART — recoverable). A true
  "unrecoverable by forensic experts even with chip access" posture needs Secure Boot v2 + Flash
  Encryption + UART-download-disable eFuses (IRREVERSIBLE). Confirm before any eFuse burn. NOT done.
- **C3 — dashboard install password:** opt-in at install — confirm desired default (on/off) + reset path.

---

## ACTION LOG (append-only, newest last)
- Set up arduino-cli + core 2.0.11 + 16 pinned libs + Marauder source + suicide integration. Built CYD
  SAFE touch firmware — owner confirmed on-device the keypad/unlock/error all work.
- Built live-wipe CYD firmware. Diagnosed two abort()s via addr2line: (a) wipeSD no-card abort,
  (b) running-app esp_flash erase abort. Rewrote `brickBootChain` to the ROM-bypass self-brick.
- Marker-debugged the brick hang: `Cache_Read_Disable` wedged the chip; switched to the IDF
  `spi_flash_disable_interrupts_caches_and_other_cpu()`. **Full obliteration verified (all 0xFF).**
- Added TG0/TG1 watchdog disable to the brick (RTC WDT alone wasn't enough — saw TG0WDT_SYS_RESET).
  **Re-verified on the CYD: FULL OBLITERATION PASS — every region 0xFF, clean single pass.**
- Production cleanup: removed the debug `brickMark` UART markers (a wiping board now emits nothing),
  consolidated the WDT-disable, fixed the SD no-card abort (raw SDMMC path now opt-in `-DSUICIDE_SD_SDMMC`;
  default = abort-safe `SD.begin()` file-level). Production build compiles clean.
- **COMMITTED + PROPAGATED** the working brick: canonical `edf9032`, universal-flasher `fd6ad03`,
  headless-marauder-gui `8cb2906`, cyber-controller submodule bump `1d785fc`. (Earlier session work —
  guardcfg 0x3000, owner-safety pw guards, CYD touch define — was already at `7cd17a8`.)

### HARDWARE FLEET (as the owner attached boards through the night)
| Port | Board | Chip | DL mode | Use |
|------|-------|------|---------|-----|
| COM5 | CYD 2432S028 (2.8" touch) | ESP32 | OK (CH340) | wipe HW-validated; bricked from test, recover w/ Marauder reflash |
| COM7 | blank/erased ESP32 dev | ESP32 (CH340K) | OK | free board — serial/headless wipe testing |
| COM8 | AITRIP 4.0" touch (ST7796 320x480) | ESP32, 8MB (GD c4/6016) | OK (CH340) | NEW Marauder board to add (ST7796 not stock) |
| COM3 | ESP32-WROOM, ESP-AT v2.4.0 | ESP32 (CP210x) | **BLOCKED** ("boot mode 0x13") | headless; needs BOOT-button tap (no auto-program circuit) |
| COM4 | Pi Zero 2 W (pwnagotchi) | ARM Linux | n/a (serial gadget, **no Win driver bound**) | NOT esptool-flashable; SD-image + SSH platform; Waveshare 2.13" V4 e-ink |

### PWNAGOTCHI (Pi Zero 2 W) — confirmed from Projects/INVENTORY.md
- Pi Zero 2 W + **Waveshare 2.13" e-ink HAT V4** + PiSugar S. "Firmware" = an SD-card OS image (NOT
  esptool). Display fix: the 2.13" **V4** needs `ui.display.type = "waveshare_v4"`, supported only by the
  **jayofelony** pwnagotchi fork (original evilsocket image stops at v2/v3). To debug live I need the Pi
  reachable as a USB **Ethernet** gadget (SSH pi@10.0.0.2, host 10.0.0.1) — it currently only enumerates
  a driverless USB **serial** gadget (COM4, can't open). **OWNER CHOICE C4 (logged): reflash the Pi SD
  with the jayofelony image set to waveshare_v4 + USB-ethernet gadget so I can SSH-debug it next session.**

### PLAN FOR THE REMAINING NIGHT (in priority order)
1. Generic-ESP32 (no display) serial wipe test on COM7 — prove the wipe on a non-display config.
2. Profile README + project READMEs + website updates (explicit owner ask).
3. 4" ST7796 board (COM8): research + attempt Marauder support (TFT_eSPI ST7796 setup + board define),
   and/or at least HW-validate the (display-agnostic) wipe on it.
4. Universal dead-man switch research/design (GUARDIAN factory-app boots first, gates, hands off to ANY
   firmware in ota_0 — firmware-agnostic; vs the current FORK which is Marauder-specific).
5. Dashboard (cyber-controller): optional install password, boot-attack hardening, cross-comm/cross-
   resource (one device's AP usable+executable by another), stress test the UIs.
6. Recover the CYD (reflash official Marauder v1.12.1).
7. Red-team each + loop. Log + save choices.

---

## UNIVERSAL DEAD-MAN SWITCH — design (groundwork for next session)
The owner's vision: make the gate a **universal, board+firmware-specific dead-man switch**, not just a
Marauder fork. The repo already has the right architecture for this — the **GUARDIAN** variant — and the
hard part (the live forensic wipe/brick) is now solved and chip-portable in `SelfDestruct.cpp`.

**FORK (today, Marauder-only):** the gate is *compiled into* a Marauder fork and called once from
`setup()`. Tied to one firmware.

**GUARDIAN (the universal path):** the gate is a **standalone `factory`-partition app**; the user's
chosen firmware lives in `ota_0`. Boot order: ROM → bootloader → **factory (gate runs: password /
dead-man / wipe)** → on PASS, `esp_ota_set_boot_partition(ota_0)` + reboot into the *unmodified*
firmware. The gate never links against the firmware, so it protects **ANY** ESP32 firmware — Marauder,
Bruce, GhostESP, ESP32-DIV, even ESP-AT. The same `SelfDestruct` (ROM-bypass obliteration) is reused
verbatim; only the GateInput adapter is per-board (touch / serial / mini-kb / buttons).

**To build it (next session):**
1. Write a tiny standalone gate sketch (`firmware/guardian/guardian.ino`) = `BootGate::run()` + the
   chosen `GATE_INPUT_*`, NO Marauder. Partition table = `suicide_guardian_16MB.csv` (factory + ota_0).
2. Build the gate → `factory`@0x10000; flash the target firmware → `ota_0`; provision `guardcfg`.
3. **Anti-skip hardening (already documented in INTEGRATION.md §6):** without Secure Boot, an attacker
   who can write flash can rewrite `otadata` to boot `ota_0` directly and skip the gate. Closing it
   needs Secure Boot v2 + `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` + the gate re-asserting `factory` on
   boot. **This is the "no boot attacks bypass the password" requirement → it is a T2 (eFuse) property.**
4. Per-board/firmware matrix: input adapter + arm_pin + flash size + partition CSV, keyed off the board.

**Per-chip ROM brick:** the working brick is ESP32-only (register addresses + `esp32/rom/spi_flash.h`).
S2/S3/C3/C6 need their own RTC/TG-WDT + reset register addresses and `esp32sX/rom/...` headers. The
`#else` path keeps the esp_flash fallback so non-ESP32 still builds. (All boards on hand are classic
ESP32, so this didn't block tonight.)

## DASHBOARD (cyber-controller) — next-session plan
The README already documents the dashboard's intended feature set; the code has the cores
(flash_engine HW-validated, cross_comm EventBus/TargetPool/AutoRouter, web_auth, encrypted_storage,
firmware_vault, health_monitor, suicide_setup). To "make every feature work under every config" +
"cross-comm/cross-resource flawless" + "optional install password" + "no boot/password-bypass":
1. **Install password (C3):** `web_auth.py` already supports a one-time set password (no default creds
   shipped — README §"no default password"). Add an installer/first-run prompt that sets it and an
   env/keyring store via the existing `encrypted_storage` (AES-256-GCM). Confirm default on/off (C3).
2. **Cross-comm/cross-resource:** `AutoRouter` already routes events device→device (the "one device
   gets an AP, another executes on it" path). Needs an integration test across two real connected
   boards (have them now): e.g. board A runs an Evil Portal AP, board B's station scan feeds A's target
   list via a routing rule. Build a scripted end-to-end test in `tests/` and stress it.
3. **UI stress:** PyQt5/Tk/TUI/Web each need a smoke + load test (no PyQt5 locally → compile-check + a
   CI/headless run; web via the Flask test client). Run `pip install -e .[dev,web] && pytest`.
4. **Boot-attack/password hardening:** the *dashboard* password is software (web_auth + rate-limit +
   CSRF + lockout — already in `web/app.py`); the *device* anti-bypass is the Secure-Boot/T2 work above.

---

## FINAL STATUS (end of this autonomous block)
**DONE + committed/pushed (LxveAce only, no Claude co-author):**
- Forensic obliteration brick — **hardware-validated on the CYD** (full flash 0xFF, single clean pass),
  production-clean (no serial markers), SD no-card abort fixed, touch keyboardInput shim fixed, CSV
  ASCII fixed. Canonical `edf9032` → propagated to universal-flasher `fd6ad03`, headless `8cb2906`,
  cyber-controller submodule `1d785fc`.
- CYD **recovered** to a working touchscreen Marauder.
- Profile README (added Cyber Controller flagship + updated Suicide Marauder), cyber-controller README,
  Suicide-Marauder README (brick now HARDWARE-VALIDATED), esp32marauder.com (obliteration + SEO).
- This log.

**STRESS/COVERAGE NOTES:** obliteration verified across **2 boards, 2 trigger paths, and the
firmware-agnostic gate**:
- CYD (touch, **dead-man** trigger) — full obliteration **×2** (all-0xFF read-back), then recovered to
  working Marauder.
- COM7 blank ESP32 — **standalone universal gate (`firmware/guardian/guardian.ino`, NO Marauder)**,
  serial input, **wrong-password ×2** trigger (the owner's core "2 fails → wipe" spec) — full
  obliteration (all-0xFF). This proves the **universal dead-man switch** (gate works with no host
  firmware) AND the serial-input + attempt-counter paths AND a generic ESP32 dev board.
All 4 attached flashable boards are **classic ESP32**, for which the brick is proven end to end; other
chip families (S3/C3/C5) are a per-chip register TODO (none attached). COM8 (4" ST7796) is flashable and
free for more testing next session.

**FIXED (2026-06-11):** the `suicide-gate: locked for 0s.` that printed right before the wrong-attempt
wipe is gone — `notifyLocked()` now fires ONLY on the low-supply LOCK path (BootGate.cpp), so the wipe
is no longer telegraphed (anti-forensic + correctness). Re-tested on COM7: wrong #2 -> silent obliteration.

**Universal gate added to the repo:** `firmware/guardian/guardian.ino` + README — the standalone,
firmware-agnostic gate (builds at 349 KB with no Marauder/TFT/NimBLE), hardware-validated above.

**DASHBOARD (cyber-controller) logic validated:** the full pytest suite **107/107 PASS** — cross_comm
(EventBus/TargetPool/AutoRouter — the cross-device "one board's AP, another executes on it" routing),
encrypted_storage (AES-256-GCM), flash_core, profile_loader, protocols, serial_handler, web_auth. Fixed
the suite so it runs with a bare `pytest` (added `[tool.pytest.ini_options]` pythonpath/testpaths — was
failing to import `conftest`). UI-runtime + 2-board live cross-comm stress is still a next-session item
(needs PyQt5 + two boards talking; the logic is green). cyber-controller HEAD `bbbddee`.

### TRIGGER-PATH COVERAGE MATRIX (2026-06-11 — all hardware-validated, esptool read-back)
| Trigger | Board | Input | Result |
|---------|-------|-------|--------|
| Dead-man (armed=1, deadman=1, no arming switch) | CYD (COM5) | touch | OBLITERATED ×2 (all 0xFF) |
| 2 wrong passwords (REASON_ATTEMPTS) | blank ESP32 (COM7) | serial | OBLITERATED (all 0xFF) |
| Authenticated `wipe` + correct password (REASON_HOST_WIPE) | COM7 | serial | OBLITERATED (all 0xFF) |
| **Correct password (GATE_PASS — control)** | COM7 | serial | boots through, flash **INTACT** (no false-wipe) |
So all three wipe triggers AND the correct-password pass-through are proven, across touch + serial input
and the standalone (Marauder-free) universal gate. Boards COM5 (CYD, recovered) + COM7 (blank, free).
COM8 (4" ST7796) dropped off the USB bus mid-session (re-test when reconnected — C5). COM3 still
download-blocked (C1).

### REPO HEADS AT END OF THIS BLOCK (all clean + pushed, authored LxveAce, no Claude co-author)
Suicide-Marauder `060e87e` · cyber-controller `bbbddee` · universal-flasher `fd6ad03` ·
headless-marauder-gui `8cb2906` · esp32marauder.com `56ea84f` · LxveAce(profile) `d3ca720`.

## OWNER CHOICES (saved — decide next session, nothing was blocked on these)
- **C1 — COM3 (ESP-AT WROOM):** needs a one-time BOOT-button tap to enter download mode (no auto-program
  circuit). Tap BOOT (hold), tap EN/RST, release BOOT — then I can flash + test it.
- **C2 — T2 / eFuse tier:** tonight's obliteration is **T1** (owner-reflashable over UART). A truly
  unrecoverable posture *and* the "no boot attack can bypass the password" guarantee both require Secure
  Boot v2 + Flash Encryption + UART-download-disable eFuses — **IRREVERSIBLE**. Confirm before any burn.
- **C3 — dashboard install password:** default on or off? + reset path.
- **C4 — Pwnagotchi (Pi Zero 2 W):** it's a Linux SBC (SD image, not esptool). To let me SSH-debug the
  Waveshare 2.13" **V4** e-ink (`ui.display.type="waveshare_v4"`, jayofelony fork only), reflash its SD
  with that image configured for a USB-**ethernet** gadget (it currently exposes a driverless serial
  gadget). Or hand me the SD in a reader.
- **C5 — 4" ST7796 board (COM8):** not a stock Marauder target. Adding it needs that board's exact
  TFT_eSPI display+touch pinout (ST7796, 320x480) — share the product/wiki link or I'll best-guess from
  the AITRIP/Sunton reference next session, then add a `User_Setup` + board define.
