# Flasher integration — how the Dead Man's Switch plugs into Cyber Controller (SHIPPED)

> **Status: implemented.** The host flasher that carries the Suicide/Dead Man's Switch path is
> **Cyber Controller** (`LxveAce/cyber-controller`), which vendors this repo as a git submodule at
> `deadmans-switch/` and imports `host/provision.py` directly. This document is the reference for
> that shipped integration — the real symbols, the real call contract, and where each piece lives.
> Additive by design: the plain-Marauder flash path is unchanged, and every duress control is behind
> an opt-in that is **off** by default. Owner-only DEFENSIVE tooling for hardware you own — a disarmed
> or unprovisioned board can never wipe (fail-safe). Plaintext passwords are hashed host-side and the
> buffer is zeroized; they are never stored, logged, or placed on a CLI argv.

> **Historical note.** An earlier draft of this plan targeted `headless-marauder-gui`
> (`marauder_core/flasher.py`, `gui_qt/app.py`). That is **not** where the integration landed —
> headless-marauder-gui stays a standalone flasher with no dead-man coupling. The provisioning + bundle
> flashing shipped in Cyber Controller instead, with the symbols below. Any doc still naming
> `marauder_core/flasher.py` / `gui_qt/app.py` `FlasherDialog` for this integration is describing the
> abandoned target — read this file as the source of truth.

---

## 0. The two halves

| Half | Repo / file | Entry point |
|------|-------------|-------------|
| **Provision** (mint `guardcfg.bin` + `bundle.json`) | this repo — `host/provision.py` | `build_bundle(args, pw_buf)` |
| **Flash** (write a provisioned bundle to the board) | cyber-controller — `src/core/flash_core.py` | `read_bundle_manifest(dir)` + `flash_suicide(...)` |

Cyber Controller wraps the provision half in `src/core/suicide_setup.py` (a thin, validated adapter)
so the GUI/CLI never touch `argparse` internals, and drives the flash half from its normal flasher.

---

## 1. Provision — `host/provision.py` (this repo)

The **real** core entry point is:

```python
def build_bundle(args, pw_buf):
    """args: an argparse.Namespace (build it with build_arg_parser() or by hand);
    pw_buf: a bytearray of the plaintext password, which is CONSUMED + ZEROIZED here.
    Returns (out_dir, manifest, file_warnings)."""
```

- It is **positional** `(args, pw_buf)` — not the keyword form `build_bundle(out_dir=…, password=…,
  tier=…)` a stale draft once showed. There is no `password=` string parameter and no `tier=`
  parameter; the password arrives as a `bytearray` (`pw_buf`) and duress fields live on `args`.
- `args` must carry: `partitions`, `out`, `variant`, `chip`, `build_dir`, `nvs_gen_dir`, `kdf_iter`,
  `armed`, `arm_pin`, `arm_level`, `arm_pull`, `deadman`, `max_att`, `wipe_ota`, `wipe_nvs`,
  `wipe_spiffs`, `wipe_sd`, `brick`, `sd_passes`, `flash_passes`, `fast_wipe`.
- `validate_args(args)` runs inside `build_bundle` as defense-in-depth (SPEC §4.1 clamps: `max_att ≥ 1`,
  fail-safe arm level/pull pairing, kdf floors, strapping-pin rejection).
- It hashes with PBKDF2-HMAC-SHA256 (`salt = os.urandom(16)`), zeroizes `pw_buf`, writes
  `guardcfg.bin` (NVS image via `esp-idf-nvs-partition-gen`), the variant's single otadata seed
  (GUARDIAN mints `otadata_blank.bin`; FORK references the build's `boot_app0.bin`), and `bundle.json`
  — the COMPLETE flash manifest whose offsets are read from the partition CSV, never hardcoded.
- `main(argv)` is the standalone CLI (reads the password via `getpass`, never argv).

## 2. Cyber Controller's provision adapter — `src/core/suicide_setup.py`

The GUI/CLI call this, **not** `build_bundle` directly:

```python
def build(cfg: SuicideConfig, password: str, out_dir) -> tuple[str, dict, list]:
    # canonicalizes + range-checks cfg (independent domain check the hand-built Namespace skips),
    # imports provision from the submodule, constructs the argparse.Namespace, then:
    #   return prov.build_bundle(args, pw_buf)   # pw_buf is zeroized by the provisioner
```

- `_load_provision()` inserts `deadmans-switch/host` on `sys.path` and `import provision`. If the
  submodule isn't checked out it raises with the exact fix: `git submodule update --init deadmans-switch`.
- `_validate_cfg()` range-checks every `guardcfg` field before the bake, so a mistyped `arm_level=5`
  fails loud host-side instead of writing a nonsense u8 to NVS.
- Partition tables resolve CC-bundled-first (`src/config/dms_partitions/`) then the submodule's, so CC
  can ship a layout (e.g. the 8 MB guardian table) the pinned submodule doesn't carry.

## 3. Flash — `src/core/flash_core.py` (cyber-controller)

```python
read_bundle_manifest(bundle_dir) -> dict     # parses bundle.json; path-traversal-hardened;
                                             # each entry needs "file" + "offset_hex"/"offset"
flash_suicide(port, chip, bundle_dir, on_line, baud=921600, profile=None) -> int
    # reads the manifest, validates each .bin is a safe in-bundle basename that exists,
    # verifies each image's SHA-256 against the manifest, stages verified copies into a fresh
    # 0700 tempdir and re-hashes (TOCTOU-safe), then writes all offset/path pairs in ONE
    # `write_flash -z --flash_size detect`. Never sees a plaintext password (guardcfg.bin is
    # already a hashed NVS image).
```

## 4. Where the UI/CLI wire in (cyber-controller)

- **CLI:** `cyber-controller --deadman-setup` → `src/app.py` → `suicide_setup.run_cli()` (interactive,
  password via `getpass`, prints next steps; guardcfg-only when no `build_dir` is given = a PREVIEW,
  re-provision with a build dir to get a flashable bundle).
- **GUI:** `src/ui/qt/suicide_dialog.py::SuicideSetupDialog` (built on `suicide_setup.build`), reachable
  from `src/ui/qt/main_window.py` (menu action, keyboard shortcut, and the "Dead Man's Switch Setup"
  command-palette entry) and from `src/ui/qt/flash_tab.py`.
- **T2 / eFuse (Secure Boot v2 + Flash Encryption)** stays a separate, explicitly type-to-confirm,
  **owner-gated** step — it is IRREVERSIBLE and is never armed silently.

## 5. Submodule pin — keep it a commit that exists on the remote

Cyber Controller records this repo as a submodule gitlink. **The pin must point at a commit reachable
from `origin/master`.** The public-history PII rewrite orphaned earlier hashes, so a stale pin makes a
fresh `git submodule update --init deadmans-switch` fail to fetch — which is exactly what breaks the
whole Dead Man's Switch path on a clean clone (the import in §2 then raises). When this repo advances,
bump the pin in cyber-controller to the new `origin/master` HEAD and re-run CC's suicide test suite.

## 6. Acceptance (all green in cyber-controller today)

- Suicide off → byte-for-byte the current flash path (regression).
- `suicide_setup.build(cfg, pw, out)` mints `guardcfg.bin` (≥ 0x3000) + `bundle.json` + honest
  incomplete-bundle warnings when no `build_dir` is given.
- Mismatched/empty password → blocked before any subprocess.
- Out-of-range cfg / non-fail-safe arm pair / `max_att < 1` → rejected before any image is written.
- `read_bundle_manifest` rejects path-traversal names and missing offsets; `flash_suicide` re-verifies
  SHA-256 atomically with the flash.
- The plaintext password never reaches a log line, a file, or argv.
