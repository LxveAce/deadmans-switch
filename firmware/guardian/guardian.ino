// guardian.ino — standalone UNIVERSAL Suicide dead-man gate (proof of concept, hardware-validated).
//
// This sketch contains NO Marauder and NO other firmware — ONLY the boot-gate. It proves the gate is
// firmware-agnostic: it runs first, gates on password / dead-man / attempt-count, and on PASS hands off
// to whatever firmware lives in `ota_0` (the GUARDIAN model). On a wrong-password / dead-man trigger it
// runs the SAME SelfDestruct forensic obliteration as the Marauder FORK. Serial input so it can be
// driven headlessly.
//
// HARDWARE-VALIDATED 2026-06-10 on a blank classic ESP32 (CH340K): built with arduino-cli (esp32 core
// 2.0.11), live wipe, flashed with a provisioned guardcfg (armed=1, deadman=0, brick=1, max_att=2), and
// a wrong-password ×2 trigger over serial OBLITERATED the entire flash (esptool read-back: bootloader,
// partition table, app, guardcfg — all 0xFF). See docs/NIGHT-SESSION-LOG.md.
//
// BUILD (from this folder's staged copy — the bootgate sources are copied in alongside, like the
// test_harness; see firmware/guardian/README.md):
//   arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs \
//     --build-property "compiler.cpp.extra_flags=-DSUICIDE_FORK -DGATE_INPUT_SERIAL \
//       -DARMING_PIN=27 -DARMING_ACTIVE_LEVEL=1 -DARMING_PULL=2" <sketchdir>
//   (add -DSUICIDE_SAFE_MODE to simulate; a live brick build is for a sacrificial board only)
//
// Anti-skip note (SPEC §6 / INTEGRATION.md §6): without Secure Boot, an attacker who can write flash
// can rewrite `otadata` to boot `ota_0` directly and skip this gate. The "no boot attack bypasses the
// password" guarantee is a T2 property — Secure Boot v2 + APP_ROLLBACK + the gate re-asserting factory.
#include <Arduino.h>
#include "esp_system.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "BootGate.h"

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== Suicide Guardian — standalone universal dead-man gate (no host firmware) ==="));

  // The one fail-closed hook. Unprovisioned / master-disarmed -> GATE_PASS (boots through, never wipes).
  if (suicide::BootGate::run() != suicide::GATE_PASS) {
    esp_restart();  // anything but PASS re-enters setup() and re-evaluates from a clean state
  }

  // GATE_PASS. In a real GUARDIAN deployment, hand off to the protected firmware in ota_0:
  const esp_partition_t* ota0 =
      esp_partition_find_first(ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_0, nullptr);
  if (ota0) {
    Serial.println(F("GATE_PASS -> handing off to the protected firmware in ota_0."));
    esp_ota_set_boot_partition(ota0);
    esp_restart();
  }
  // No ota_0 present (this proof-of-concept layout): just simulate the protected firmware running.
  Serial.println(F("GATE_PASS -> no ota_0; protected firmware would run here (simulated)."));
}

void loop() {
  Serial.println(F("[protected firmware running]"));
  delay(3000);
}
