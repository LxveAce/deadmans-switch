# Suicide Marauder — Host Provisioner (`host/provision.py`)

Owner-only, **defensive** anti-forensic ("duress") provisioning for an ESP32 Marauder you own.
This tool bakes a per-device `guardcfg` NVS partition image, a blank `otadata` blob, and a flash
bundle manifest. It is the host side of the contract in [`../docs/SPEC.md`](../docs/SPEC.md)
sections **4** (NVS schema), **9** (cryptography), and **10** (host provisioning).

> A non-provisioned **or** master-disarmed board can never wipe. Provisioning defaults to
> `armed=0` (DISARMED). See [`../docs/SAFETY.md`](../docs/SAFETY.md) and
> [`../docs/THREAT-MODEL.md`](../docs/THREAT-MODEL.md).

---

## What it produces

Running `provision.py` writes three files into the output bundle directory (default `build/bundle`):

| File | Contents | Flash offset |
|------|----------|--------------|
| `guardcfg.bin` | NVS image of namespace `sgate`, sized to the `guardcfg` partition | `guardcfg` offset (read from CSV) |
| `otadata_blank.bin` | `0xFF` fill, sized to the `otadata` partition (forces first boot into factory/Guardian; FORK ignores it) | `otadata` offset (read from CSV) |
| `bundle.json` | manifest of `{file, offset}` pairs + KDF params | — |

**Offsets are READ from the partitions CSV you pass — never hardcoded.** Marauder's `otadata`
lives at `0xe000` (not the stock `0xd000`) because it enlarges `nvs`; the manifest reflects
whatever your chosen partition table actually says.

---

## The KDF contract (must match the device byte-for-byte)

The device (`firmware/bootgate/GateCrypto`) re-derives the hash from the entered password plus the
stored `{salt, kdf_iter, kdf_dklen}` and compares constant-time against `pwhash`. Host and device
**must** agree:

- Algorithm: **PBKDF2-HMAC-SHA256** (stdlib `hashlib.pbkdf2_hmac('sha256', pw, salt, iter, 32)`).
- `salt = os.urandom(16)` — 16 bytes, fresh per device.
- `kdf_iter` default **10000** (matches `provision.py` `DEFAULT_KDF_ITER` and SPEC §9; `--kdf-iter`
  to tune; ~1 s verify on a classic ESP32 — `150000` measured ≈16.7 s, far too slow for a boot gate.
  Keep host + device identical).
- `kdf_dklen = 32`.

**Argon2id is intentionally not used** — OWASP's 19 MiB minimum exceeds ESP32 RAM (SPEC §9).

### Password handling (non-negotiable)

- The password is read **only** via `getpass` (hidden input). It is **never** a CLI argument,
  **never** logged, and **never** written to the bundle.
- It lives in a `bytearray` that is **zeroized** immediately after hashing.
- Only `{salt, pwhash, kdf_iter, kdf_dklen}` ever reach the device. A raw NVS dump reveals the
  salted hash, not the passphrase.

---

## Dependency note (esptool does NOT bundle the NVS generator)

`provision.py` is pure Python 3.9+ standard library for everything security-relevant. The single
external dependency is the **NVS partition image generator**, which is **confirmed not bundled**
with `pip install esptool`. Provide it in any one of these ways:

1. **pip (recommended):**
   ```
   pip install -r requirements.txt          # installs esp-idf-nvs-partition-gen
   ```
2. **Vendor it:** drop the IDF release-branch `nvs_partition_gen.py` (Apache-2.0) into
   `host/vendor/nvs_partition_gen.py`. `provision.py` auto-discovers it there.
3. **Point at a copy:** `--nvs-gen-dir /path/to/dir/containing/nvs_partition_gen.py`.

If none is available, `provision.py` exits with an actionable message — it does not crash.

Requires Python **3.9+**.

---

## Usage

```
python provision.py --partitions ../firmware/partitions/suicide_4MB.csv
```

You will be prompted (hidden) for the password and a confirmation. Defaults are DISARMED and
follow SPEC §4. To override config (all optional):

```
python provision.py \
  --partitions ../firmware/partitions/suicide_4MB.csv \
  --out build/bundle \
  --arm-pin 27 --arm-level 1 --arm-pull 2 \
  --max-att 2 --deadman 1 \
  --wipe-ota 1 --wipe-nvs 1 --wipe-spiffs 1 --wipe-sd 1 --sd-passes 1 \
  --brick 0 \
  --kdf-iter 10000 \
  --armed 0
```

### CLI flags

| Flag | NVS key | Default | Meaning |
|------|---------|---------|---------|
| `--partitions CSV` | — | **required** | partition table to read `guardcfg`/`otadata` offsets+sizes from |
| `--out DIR` | — | `build/bundle` | output bundle directory |
| `--arm-pin N` | `arm_pin` | `27` | dead-man GPIO (never a strapping pin — see SPEC §7) |
| `--arm-level {0,1}` | `arm_level` | `1` | logic level meaning ARMED (1=HIGH) |
| `--arm-pull {0,1,2}` | `arm_pull` | `2` | 0=none, 1=pullup, 2=pulldown |
| `--max-att N` | `max_att` | `2` | wrong-password attempts before wipe |
| `--deadman {0,1}` | `deadman` | `1` | 1=cut/disarmed line wipes; 0=line only locks |
| `--armed {0,1}` | `armed` | `0` | **master arm** — `0` is the safe default |
| `--wipe-ota {0,1}` | `wipe_ota` | `1` | erase Marauder app slot |
| `--wipe-nvs {0,1}` | `wipe_nvs` | `1` | erase Marauder NVS |
| `--wipe-spiffs {0,1}` | `wipe_spiffs` | `1` | erase SPIFFS |
| `--wipe-sd {0,1}` | `wipe_sd` | `1` | overwrite + erase SD |
| `--sd-passes N` | `sd_passes` | `1` | SD overwrite passes (extra passes give no real gain on flash) |
| `--brick {0,1}` | `brick` | `0` | erase boot chain last for a true brick (T2 sets 1) |
| `--kdf-iter N` | `kdf_iter` | `10000` | PBKDF2 iterations — must match the device (SPEC §9) |
| `--no-confirm` | — | off | skip the password confirmation prompt |
| `--nvs-gen-dir DIR` | — | auto | directory holding a vendored `nvs_partition_gen.py` |

> The runtime counter namespace `sgate_rt` (`att_ct`, `lock_until`) is **not** written by the
> host — the device creates it with a clean, zeroed counter so a fresh board starts at attempt 0.

---

## Flashing the bundle

`provision.py` only produces the per-device data images. The full flash (bootloader, partition
table, `boot_app0`, app, plus `guardcfg.bin` and `otadata_blank.bin` at the manifest offsets) is
assembled by the flasher integration — see SPEC §11 and the `headless-marauder-gui` integration.
The manifest's offsets are authoritative; do not hardcode `0xe000`.

---

## Files in this directory

- `provision.py` — the provisioner (stdlib + the NVS generator dependency).
- `nvs_config.csv.template` — documentation of the exact `sgate` rows emitted (placeholders for
  salt/hash filled at provision time; **never contains the plaintext password**).
- `requirements.txt` — the single external dependency plus a convenience `esptool` pin.
